from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import yfinance as yf

from .config import OUTPUT_DIR, PORTFOLIO_SYMBOLS
from .provenance import SourceKind

_LIVE_CACHE = OUTPUT_DIR / "prices_live.csv"
_LIVE_META = OUTPUT_DIR / "prices_live.meta.json"

_BASE_PRICES = {
    "GLD": 180.0,
    "SPY": 480.0,
    "TLT": 95.0,
    "VNQ": 85.0,
    "GC=F": 2000.0,
    "XAUUSD=X": 2000.0,
    "SLV": 22.0,
}


class DataUnavailableError(RuntimeError):
    """Raised when no real data is available and synthetic fallback is disabled."""


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class PriceDataset:
    """A price series together with the provenance required by the Wasl spec."""

    frame: pd.DataFrame
    kind: SourceKind
    source: str
    fetched_at: str
    symbols: tuple[str, ...]
    note: str | None = None

    def labeled_frame(self) -> pd.DataFrame:
        """Wide frame with a source label repeated on every row."""
        out = self.frame.copy()
        out.index.name = "Date"
        out.insert(0, "source_kind", self.kind.value)
        out.insert(1, "source", self.source)
        out.insert(2, "fetched_at", self.fetched_at)
        return out

    @property
    def is_real_market_data(self) -> bool:
        return self.kind in (SourceKind.LIVE, SourceKind.CACHED)

    @property
    def is_synthetic(self) -> bool:
        return self.kind is SourceKind.SYNTHETIC

    def provenance(self) -> dict[str, object]:
        return {
            "kind": self.kind.value,
            "source": self.source,
            "fetched_at": self.fetched_at,
            "symbols": list(self.symbols),
            "is_real_market_data": self.is_real_market_data,
            "note": self.note,
        }


def synthetic_prices(
    symbols: list[str] | tuple[str, ...], periods: int = 520
) -> pd.DataFrame:
    """Deterministic offline fallback. Never label these rows as market data."""
    rng = np.random.default_rng(42)
    dates = pd.bdate_range(end=pd.Timestamp.today().normalize(), periods=periods)
    columns: dict[str, np.ndarray] = {}
    for index, symbol in enumerate(symbols):
        drift = 0.0003 + index * 0.00005
        volatility = 0.01 + index * 0.001
        steps = rng.normal(drift, volatility, periods)
        columns[symbol] = _BASE_PRICES.get(symbol, 100.0) * np.exp(np.cumsum(steps))
    return pd.DataFrame(columns, index=dates)


def download_live_prices(
    symbols: list[str] | tuple[str, ...], period: str = "2y"
) -> pd.DataFrame:
    """Download adjusted closes. Raises if any requested symbol is missing."""
    symbols = tuple(symbols)
    raw = yf.download(
        list(symbols),
        period=period,
        auto_adjust=True,
        progress=False,
        threads=False,
    )
    if isinstance(raw.columns, pd.MultiIndex):
        close = raw["Close"]
    else:
        close = raw[["Close"]].rename(columns={"Close": symbols[0]})
    close = (
        close.reindex(columns=list(symbols))
        .dropna(how="all")
        .dropna(axis=1, how="all")
        .tail(520)
    )
    missing = [s for s in symbols if s not in close.columns or close[s].dropna().empty]
    if close.empty or missing:
        raise ValueError(
            "empty or incomplete yfinance response"
            + (f" (missing: {', '.join(missing)})" if missing else "")
        )
    return close[list(symbols)]


def _write_live_cache(
    frame: pd.DataFrame, symbols: tuple[str, ...], fetched_at: str
) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    frame.to_csv(_LIVE_CACHE)
    _LIVE_META.write_text(
        json.dumps(
            {"fetched_at": fetched_at, "symbols": list(symbols), "source": "yfinance"},
            indent=2,
        ),
        encoding="utf-8",
    )


def _read_live_cache(
    symbols: tuple[str, ...],
) -> tuple[pd.DataFrame, str] | None:
    if not _LIVE_CACHE.exists():
        return None
    try:
        frame = pd.read_csv(_LIVE_CACHE, index_col=0, parse_dates=True)
        meta: dict[str, object] = {}
        if _LIVE_META.exists():
            meta = json.loads(_LIVE_META.read_text(encoding="utf-8"))
        cached_symbols = meta.get("symbols", list(frame.columns))
        if set(cached_symbols) != set(symbols):
            return None
        if any(s not in frame.columns for s in symbols):
            return None
        fetched_at = str(
            meta.get("fetched_at")
            or datetime.fromtimestamp(_LIVE_CACHE.stat().st_mtime, timezone.utc).isoformat()
        )
        return frame[list(symbols)], fetched_at
    except Exception:
        return None


def load_prices(
    symbols: list[str] | tuple[str, ...],
    period: str = "2y",
    *,
    allow_live: bool = True,
    allow_cache: bool = True,
    allow_synthetic: bool = True,
) -> PriceDataset:
    """Load prices with an explicit provenance label.

    Resolution order: live provider -> cached live snapshot -> synthetic demo.
    The three sources are never mixed inside one dataset.
    """
    symbols = tuple(symbols)
    live_error: str | None = None

    if allow_live:
        try:
            frame = download_live_prices(symbols, period=period)
            fetched_at = _utcnow()
            _write_live_cache(frame, symbols, fetched_at)
            return PriceDataset(
                frame=frame,
                kind=SourceKind.LIVE,
                source="yfinance",
                fetched_at=fetched_at,
                symbols=symbols,
            )
        except Exception as error:  # yfinance and network errors vary widely
            live_error = f"{type(error).__name__}: {error}"
    else:
        live_error = "live fetch disabled by caller"

    if allow_cache:
        cached = _read_live_cache(symbols)
        if cached is not None:
            frame, fetched_at = cached
            return PriceDataset(
                frame=frame,
                kind=SourceKind.CACHED,
                source="local-cache",
                fetched_at=fetched_at,
                symbols=symbols,
                note=live_error,
            )

    if allow_synthetic:
        return PriceDataset(
            frame=synthetic_prices(symbols),
            kind=SourceKind.SYNTHETIC,
            source="offline-generator",
            fetched_at=_utcnow(),
            symbols=symbols,
            note=live_error or "offline demo requested",
        )

    raise DataUnavailableError(
        "No live or cached market data available; synthetic fallback is disabled. "
        f"Last live error: {live_error}"
    )


def latest_quotes(
    symbols: list[str] | tuple[str, ...],
    *,
    period: str = "1mo",
    allow_live: bool = True,
    allow_cache: bool = True,
    allow_synthetic: bool = True,
) -> list[dict[str, object]]:
    """Quote snapshot where every row carries its own source label."""
    dataset = load_prices(
        symbols,
        period=period,
        allow_live=allow_live,
        allow_cache=allow_cache,
        allow_synthetic=allow_synthetic,
    )
    rows: list[dict[str, object]] = []
    for symbol in symbols:
        if symbol not in dataset.frame.columns:
            continue
        series = dataset.frame[symbol].dropna()
        if series.empty:
            continue
        last = float(series.iloc[-1])
        previous = float(series.iloc[-2]) if len(series) > 1 else last
        change = last - previous
        rows.append(
            {
                "symbol": symbol,
                "price": round(last, 4),
                "change": round(change, 4),
                "change_percent": round(change / previous * 100, 4) if previous else 0.0,
                "as_of": series.index[-1].date().isoformat(),
                "source_kind": dataset.kind.value,
                "source": dataset.source,
                "fetched_at": dataset.fetched_at,
                "note": dataset.note or "",
            }
        )
    return rows


def save_prices(dataset: PriceDataset, name: str = "prices.csv") -> Path:
    """Persist prices with per-row provenance columns."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / name
    dataset.labeled_frame().to_csv(path)
    return path


# Backwards-compatible helper for callers that only need the numeric frame.
def download_prices(
    symbols: list[str] | tuple[str, ...], period: str = "2y"
) -> pd.DataFrame:
    """Return only the numeric frame. Prefer ``load_prices`` for provenance."""
    return load_prices(symbols, period=period).frame


__all__ = [
    "PORTFOLIO_SYMBOLS",
    "DataUnavailableError",
    "PriceDataset",
    "download_live_prices",
    "download_prices",
    "latest_quotes",
    "load_prices",
    "save_prices",
    "synthetic_prices",
]
