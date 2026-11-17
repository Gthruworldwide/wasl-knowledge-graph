from __future__ import annotations

import numpy as np
import pandas as pd
import yfinance as yf

from .config import OUTPUT_DIR, PORTFOLIO_SYMBOLS

_BASE_PRICES = {
    "GLD": 180.0,
    "SPY": 480.0,
    "TLT": 95.0,
    "VNQ": 85.0,
    "GC=F": 2000.0,
    "XAUUSD=X": 2000.0,
    "SLV": 22.0,
}


def synthetic_prices(symbols: list[str] | tuple[str, ...], periods: int = 520) -> pd.DataFrame:
    """Deterministic offline fallback so the lab works without network access."""
    rng = np.random.default_rng(42)
    dates = pd.bdate_range(end=pd.Timestamp.today().normalize(), periods=periods)
    columns: dict[str, np.ndarray] = {}
    for index, symbol in enumerate(symbols):
        drift = 0.0003 + index * 0.00005
        volatility = 0.01 + index * 0.001
        steps = rng.normal(drift, volatility, periods)
        columns[symbol] = _BASE_PRICES.get(symbol, 100.0) * np.exp(np.cumsum(steps))
    return pd.DataFrame(columns, index=dates)


def download_prices(
    symbols: list[str] | tuple[str, ...],
    period: str = "2y",
) -> pd.DataFrame:
    """Download adjusted closes; fall back to synthetic data if Yahoo fails."""
    try:
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
        if close.empty or close.notna().to_numpy().sum() == 0:
            raise ValueError("empty response")
        return close
    except Exception:
        return synthetic_prices(symbols)


def latest_quotes(symbols: list[str] | tuple[str, ...]) -> list[dict[str, object]]:
    """Build a small quote snapshot from recent daily closes."""
    prices = download_prices(symbols, period="1mo")
    rows: list[dict[str, object]] = []
    for symbol in symbols:
        if symbol not in prices.columns:
            continue
        series = prices[symbol].dropna()
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
            }
        )
    return rows


def save_prices(prices: pd.DataFrame, name: str = "prices.csv") -> object:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / name
    prices.to_csv(path)
    return path


__all__ = [
    "PORTFOLIO_SYMBOLS",
    "download_prices",
    "latest_quotes",
    "save_prices",
    "synthetic_prices",
]
