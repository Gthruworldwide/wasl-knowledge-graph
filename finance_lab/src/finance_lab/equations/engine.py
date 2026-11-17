"""Deterministic implementations of the catalog formulas.

Rules enforced everywhere:
* missing, zero-denominator or otherwise invalid inputs return ``defined=False``
  with a machine-readable reason instead of a fabricated zero;
* synthetic and real inputs are never mixed;
* currency, unit and period compatibility is checked before computing.
"""

from __future__ import annotations

import math
import statistics
from datetime import timedelta

from ..provenance import SourceKind, is_real_market_data
from .types import (
    IndicatorResult,
    MetricInput,
    MetricResult,
    Unit,
    undefined,
)

_IDS = {
    "net_worth": "wealth.net_worth",
    "weekly_change": "wealth.weekly_change_isoweek",
    "income_share": "wealth.income_source_share",
    "income_hhi": "wealth.income_source_hhi",
    "revenue_growth": "business.revenue_growth",
    "gross_margin": "business.gross_margin",
    "net_margin": "business.net_margin",
    "debt_to_equity": "business.debt_to_equity",
    "roi": "business.roi",
    "simple_return": "market.simple_return",
    "cumulative_return": "market.cumulative_return",
    "cagr": "market.cagr",
    "portfolio_return": "portfolio.expected_return",
    "volatility": "portfolio.annualized_volatility",
    "sharpe": "portfolio.sharpe_ratio",
    "max_drawdown": "portfolio.max_drawdown",
    "real_return": "portfolio.real_return_after_inflation",
    "price_change": "market.price_change",
    "sma": "indicator.sma",
    "macd": "indicator.macd",
    "rsi": "indicator.rsi_wilder",
}


def _number(item: MetricInput | None) -> float | None:
    if item is None or item.value is None:
        return None
    value = float(item.value)
    return value if math.isfinite(value) else None


def _currencies_ok(items: tuple[MetricInput, ...]) -> bool:
    present = {item.currency for item in items if item.currency is not None}
    if len(present) > 1:
        return False
    return not present or all(item.currency is not None for item in items)


def _periods_ok(items: tuple[MetricInput, ...]) -> bool:
    if all(item.period is None for item in items):
        return True
    if any(item.period is None for item in items):
        return False
    return len({item.period.label for item in items if item.period}) == 1


def _units_ok(items: tuple[MetricInput, ...], unit: Unit) -> bool:
    return bool(items) and all(item.unit is unit for item in items)


def _common(items: tuple[MetricInput, ...]):
    """Return shared metadata, or ``None`` when real and synthetic are mixed."""
    real = [is_real_market_data(item.source_kind) for item in items]
    if any(real) and not all(real):
        return None
    currency = next((item.currency for item in items if item.currency), None)
    period = next((item.period for item in items if item.period), None)
    as_of = max((item.as_of for item in items if item.as_of), default=None)
    source = next((item.source for item in items if item.source), None)
    kind = items[0].source_kind if items else SourceKind.MANUAL
    return currency, period, as_of, source, kind


def _finish(
    key: str,
    unit: Unit,
    items: tuple[MetricInput, ...],
    value: float | None,
    *,
    reason: str | None = None,
    qualifier: str | None = None,
) -> MetricResult:
    id_ = _IDS[key]
    common = _common(items)
    if common is None:
        return undefined(
            id_, "mixed_provenance", unit=unit, inputs=tuple(i.source or "input" for i in items)
        )
    currency, period, as_of, source, kind = common
    inputs = tuple(item.source or item.unit.value for item in items)
    return MetricResult(
        id=id_,
        value=value,
        unit=unit,
        currency=currency,
        period=period,
        as_of=as_of,
        source=source,
        source_kind=kind,
        defined=reason is None and value is not None,
        reason=reason,
        qualifier=qualifier,
        inputs=inputs,
    )


def _bad(
    key: str,
    unit: Unit,
    items: tuple[MetricInput, ...],
    reason: str,
) -> MetricResult:
    return _finish(key, unit, items, None, reason=reason)


# ---------------------------------------------------------------- wealth


def net_worth(assets: MetricInput, liabilities: MetricInput) -> MetricResult:
    items = (assets, liabilities)
    a, l = _number(assets), _number(liabilities)
    if a is None or l is None:
        return _bad("net_worth", Unit.CURRENCY, items, "missing_input")
    if not _units_ok(items, Unit.CURRENCY):
        return _bad("net_worth", Unit.CURRENCY, items, "incompatible_unit")
    if not _currencies_ok(items):
        return _bad("net_worth", Unit.CURRENCY, items, "incompatible_currency")
    return _finish("net_worth", Unit.CURRENCY, items, a - l)


def weekly_change(current: MetricInput, previous: MetricInput) -> MetricResult:
    items = (current, previous)
    unit = Unit.PERCENT
    c, p = _number(current), _number(previous)
    if c is None or p is None:
        return _bad("weekly_change", unit, items, "missing_input")
    if not _units_ok(items, Unit.CURRENCY) or not _currencies_ok(items):
        return _bad("weekly_change", unit, items, "incompatible_input")
    if current.period is None or previous.period is None:
        return _bad("weekly_change", unit, items, "missing_period")
    if current.period.start is None or previous.period.start is None:
        return _bad("weekly_change", unit, items, "missing_period")
    if current.period.start - previous.period.start != timedelta(days=7):
        return _bad("weekly_change", unit, items, "non_consecutive_iso_weeks")
    if p == 0:
        return _bad("weekly_change", unit, items, "zero_denominator")
    return _finish("weekly_change", unit, items, (c - p) / p * 100)


def income_source_share(source: MetricInput, total: MetricInput) -> MetricResult:
    items = (source, total)
    s, t = _number(source), _number(total)
    if s is None or t is None:
        return _bad("income_share", Unit.PERCENT, items, "missing_input")
    if not _units_ok(items, Unit.CURRENCY) or not _currencies_ok(items):
        return _bad("income_share", Unit.PERCENT, items, "incompatible_input")
    if t <= 0:
        return _bad("income_share", Unit.PERCENT, items, "zero_denominator")
    qualifier = "estimated" if (source.estimated or total.estimated) else None
    return _finish(
        "income_share", Unit.PERCENT, items, s / t * 100, qualifier=qualifier
    )


def income_hhi(shares: tuple[MetricInput, ...]) -> MetricResult:
    unit = Unit.INDEX
    if not shares:
        return _bad("income_hhi", unit, (), "missing_input")
    if not _units_ok(shares, Unit.RATIO):
        return _bad("income_hhi", unit, shares, "incompatible_unit")
    values = [_number(item) for item in shares]
    if any(v is None for v in values):
        return _bad("income_hhi", unit, shares, "missing_input")
    if abs(sum(v or 0 for v in values) - 1.0) > 1e-6:
        return _bad("income_hhi", unit, shares, "invalid_share_sum")
    return _finish("income_hhi", unit, shares, sum((v or 0) ** 2 for v in values))


# --------------------------------------------------------------- business


def revenue_growth(current: MetricInput, prior: MetricInput) -> MetricResult:
    items = (current, prior)
    c, p = _number(current), _number(prior)
    if c is None or p is None:
        return _bad("revenue_growth", Unit.PERCENT, items, "missing_input")
    if not _units_ok(items, Unit.CURRENCY) or not _currencies_ok(items):
        return _bad("revenue_growth", Unit.PERCENT, items, "incompatible_input")
    if not _periods_ok(items):
        return _bad("revenue_growth", Unit.PERCENT, items, "incompatible_period")
    if p == 0:
        return _bad("revenue_growth", Unit.PERCENT, items, "zero_denominator")
    return _finish("revenue_growth", Unit.PERCENT, items, (c / p - 1) * 100)


def gross_margin(revenue: MetricInput, cogs: MetricInput) -> MetricResult:
    items = (revenue, cogs)
    r, c = _number(revenue), _number(cogs)
    if r is None or c is None:
        return _bad("gross_margin", Unit.PERCENT, items, "missing_input")
    if not _units_ok(items, Unit.CURRENCY) or not _currencies_ok(items):
        return _bad("gross_margin", Unit.PERCENT, items, "incompatible_input")
    if r == 0:
        return _bad("gross_margin", Unit.PERCENT, items, "zero_denominator")
    return _finish("gross_margin", Unit.PERCENT, items, (r - c) / r * 100)


def net_margin(net_income: MetricInput, revenue: MetricInput) -> MetricResult:
    items = (net_income, revenue)
    n, r = _number(net_income), _number(revenue)
    if n is None or r is None:
        return _bad("net_margin", Unit.PERCENT, items, "missing_input")
    if not _units_ok(items, Unit.CURRENCY) or not _currencies_ok(items):
        return _bad("net_margin", Unit.PERCENT, items, "incompatible_input")
    if r == 0:
        return _bad("net_margin", Unit.PERCENT, items, "zero_denominator")
    return _finish("net_margin", Unit.PERCENT, items, n / r * 100)


def debt_to_equity(debt: MetricInput, equity: MetricInput) -> MetricResult:
    items = (debt, equity)
    d, e = _number(debt), _number(equity)
    if d is None or e is None:
        return _bad("debt_to_equity", Unit.RATIO, items, "missing_input")
    if not _units_ok(items, Unit.CURRENCY) or not _currencies_ok(items):
        return _bad("debt_to_equity", Unit.RATIO, items, "incompatible_input")
    if e == 0:
        return _bad("debt_to_equity", Unit.RATIO, items, "zero_denominator")
    return _finish("debt_to_equity", Unit.RATIO, items, d / e)


def roi(final_value: MetricInput, cost: MetricInput) -> MetricResult:
    items = (final_value, cost)
    f, c = _number(final_value), _number(cost)
    if f is None or c is None:
        return _bad("roi", Unit.PERCENT, items, "missing_input")
    if not _units_ok(items, Unit.CURRENCY) or not _currencies_ok(items):
        return _bad("roi", Unit.PERCENT, items, "incompatible_input")
    if c == 0:
        return _bad("roi", Unit.PERCENT, items, "zero_denominator")
    return _finish("roi", Unit.PERCENT, items, (f - c) / c * 100)


# ------------------------------------------------------- markets/portfolio


def simple_return(current: MetricInput, previous: MetricInput) -> MetricResult:
    items = (current, previous)
    c, p = _number(current), _number(previous)
    if c is None or p is None:
        return _bad("simple_return", Unit.RATIO, items, "missing_input")
    if not _units_ok(items, Unit.PRICE) or not _currencies_ok(items):
        return _bad("simple_return", Unit.RATIO, items, "incompatible_input")
    if p <= 0:
        return _bad("simple_return", Unit.RATIO, items, "non_positive_value")
    return _finish("simple_return", Unit.RATIO, items, c / p - 1)


def cumulative_return(returns: tuple[MetricInput, ...]) -> MetricResult:
    if not returns:
        return _bad("cumulative_return", Unit.RATIO, (), "insufficient_observations")
    if not _units_ok(returns, Unit.RATIO):
        return _bad("cumulative_return", Unit.RATIO, returns, "incompatible_unit")
    values = [_number(item) for item in returns]
    if any(v is None for v in values):
        return _bad("cumulative_return", Unit.RATIO, returns, "missing_input")
    if any((v or 0) <= -1 for v in values):
        return _bad("cumulative_return", Unit.RATIO, returns, "invalid_return")
    growth = 1.0
    for value in values:
        growth *= 1 + (value or 0)
    return _finish("cumulative_return", Unit.RATIO, returns, growth - 1)


def cagr(
    start_value: MetricInput,
    end_value: MetricInput,
    start_date: object,
    end_date: object,
) -> MetricResult:
    items = (start_value, end_value)
    s, e = _number(start_value), _number(end_value)
    if s is None or e is None:
        return _bad("cagr", Unit.RATIO, items, "missing_input")
    if start_value.unit is not end_value.unit or not _currencies_ok(items):
        return _bad("cagr", Unit.RATIO, items, "incompatible_input")
    if s <= 0 or e <= 0:
        return _bad("cagr", Unit.RATIO, items, "non_positive_value")
    try:
        days = (end_date - start_date).days  # type: ignore[operator]
    except Exception:
        return _bad("cagr", Unit.RATIO, items, "invalid_period")
    if days <= 0:
        return _bad("cagr", Unit.RATIO, items, "invalid_period")
    years = days / 365.25
    return _finish("cagr", Unit.RATIO, items, (e / s) ** (1 / years) - 1)


def portfolio_expected_return(
    weights: tuple[MetricInput, ...], expected_returns: tuple[MetricInput, ...]
) -> MetricResult:
    items = weights + expected_returns
    if not weights or len(weights) != len(expected_returns):
        return _bad("portfolio_return", Unit.RATIO, items, "invalid_weight_vector")
    if not _units_ok(weights, Unit.RATIO) or not _units_ok(expected_returns, Unit.RATIO):
        return _bad("portfolio_return", Unit.RATIO, items, "incompatible_unit")
    w = [_number(item) for item in weights]
    mu = [_number(item) for item in expected_returns]
    if any(v is None for v in w + mu):
        return _bad("portfolio_return", Unit.RATIO, items, "missing_input")
    if abs(sum(v or 0 for v in w) - 1.0) > 1e-6:
        return _bad("portfolio_return", Unit.RATIO, items, "invalid_weight_sum")
    return _finish(
        "portfolio_return",
        Unit.RATIO,
        items,
        sum((a or 0) * (b or 0) for a, b in zip(w, mu)),
    )


def annualized_volatility(daily_returns: tuple[MetricInput, ...]) -> MetricResult:
    if len(daily_returns) < 20:
        return _bad(
            "volatility", Unit.RATIO, daily_returns, "insufficient_observations"
        )
    if not _units_ok(daily_returns, Unit.RATIO):
        return _bad("volatility", Unit.RATIO, daily_returns, "incompatible_unit")
    values = [_number(item) for item in daily_returns]
    if any(v is None for v in values):
        return _bad("volatility", Unit.RATIO, daily_returns, "missing_input")
    return _finish(
        "volatility",
        Unit.RATIO,
        daily_returns,
        statistics.stdev([v or 0 for v in values]) * math.sqrt(252),
    )


def sharpe_ratio(
    annual_return: MetricInput,
    risk_free_rate: MetricInput,
    annual_volatility: MetricInput,
) -> MetricResult:
    items = (annual_return, risk_free_rate, annual_volatility)
    r, f, v = _number(annual_return), _number(risk_free_rate), _number(annual_volatility)
    if r is None or f is None or v is None:
        return _bad("sharpe", Unit.RATIO, items, "missing_input")
    if not _units_ok(items, Unit.RATIO):
        return _bad("sharpe", Unit.RATIO, items, "incompatible_unit")
    if v <= 0:
        return _bad("sharpe", Unit.RATIO, items, "zero_denominator")
    return _finish("sharpe", Unit.RATIO, items, (r - f) / v)


def max_drawdown(values: tuple[MetricInput, ...]) -> MetricResult:
    if len(values) < 2:
        return _bad("max_drawdown", Unit.RATIO, values, "insufficient_observations")
    if not _units_ok(values, Unit.PRICE):
        return _bad("max_drawdown", Unit.RATIO, values, "incompatible_unit")
    numbers = [_number(item) for item in values]
    if any(v is None for v in numbers):
        return _bad("max_drawdown", Unit.RATIO, values, "missing_input")
    peak = numbers[0] or 0.0
    worst = 0.0
    for value in numbers:
        current = value or 0.0
        peak = max(peak, current)
        if peak > 0:
            worst = min(worst, current / peak - 1)
    return _finish("max_drawdown", Unit.RATIO, values, worst)


def real_return(nominal: MetricInput, inflation: MetricInput) -> MetricResult:
    items = (nominal, inflation)
    n, i = _number(nominal), _number(inflation)
    if n is None or i is None:
        return _bad("real_return", Unit.RATIO, items, "missing_input")
    if not _units_ok(items, Unit.RATIO):
        return _bad("real_return", Unit.RATIO, items, "incompatible_unit")
    if i <= -1:
        return _bad("real_return", Unit.RATIO, items, "invalid_inflation_rate")
    return _finish("real_return", Unit.RATIO, items, (1 + n) / (1 + i) - 1)


def price_change(current: MetricInput, previous: MetricInput) -> MetricResult:
    items = (current, previous)
    c, p = _number(current), _number(previous)
    if c is None or p is None:
        return _bad("price_change", Unit.PERCENT, items, "missing_input")
    if not _units_ok(items, Unit.PRICE) or not _currencies_ok(items):
        return _bad("price_change", Unit.PERCENT, items, "incompatible_input")
    if p <= 0:
        return _bad("price_change", Unit.PERCENT, items, "non_positive_value")
    return _finish("price_change", Unit.PERCENT, items, (c / p - 1) * 100)


# ------------------------------------------------------------- indicators


def _ema(values: list[float], span: int) -> list[float]:
    alpha = 2 / (span + 1)
    out: list[float] = []
    previous: float | None = None
    for value in values:
        previous = value if previous is None else alpha * value + (1 - alpha) * previous
        out.append(previous)
    return out


def sma(prices: tuple[MetricInput, ...], window: int = 20) -> IndicatorResult:
    if window < 1 or window > len(prices):
        return IndicatorResult(_IDS["sma"], (), None, Unit.PRICE, defined=False, reason="invalid_window")
    if not _units_ok(prices, Unit.PRICE):
        return IndicatorResult(_IDS["sma"], (), None, Unit.PRICE, defined=False, reason="incompatible_unit")
    numbers = [_number(item) for item in prices]
    if any(v is None for v in numbers):
        return IndicatorResult(_IDS["sma"], (), None, Unit.PRICE, defined=False, reason="missing_input")
    values: list[float | None] = [None] * (window - 1)
    for index in range(window - 1, len(numbers)):
        values.append(sum(numbers[index - window + 1 : index + 1]) / window)  # type: ignore[arg-type]
    return IndicatorResult(_IDS["sma"], tuple(values), values[-1], Unit.PRICE)


def macd(prices: tuple[MetricInput, ...]) -> IndicatorResult:
    if len(prices) < 26:
        return IndicatorResult(_IDS["macd"], (), None, Unit.PRICE, defined=False, reason="insufficient_observations")
    if not _units_ok(prices, Unit.PRICE):
        return IndicatorResult(_IDS["macd"], (), None, Unit.PRICE, defined=False, reason="incompatible_unit")
    numbers = [_number(item) for item in prices]
    if any(v is None for v in numbers):
        return IndicatorResult(_IDS["macd"], (), None, Unit.PRICE, defined=False, reason="missing_input")
    clean = [v or 0.0 for v in numbers]
    fast, slow = _ema(clean, 12), _ema(clean, 26)
    line = [f - s for f, s in zip(fast, slow)]
    signal = _ema(line, 9)
    return IndicatorResult(_IDS["macd"], tuple(line), line[-1], Unit.PRICE, tuple(signal))


def rsi_wilder(prices: tuple[MetricInput, ...], window: int = 14) -> IndicatorResult:
    if window < 1 or len(prices) < window + 1:
        return IndicatorResult(_IDS["rsi"], (), None, Unit.PERCENT, defined=False, reason="insufficient_observations")
    if not _units_ok(prices, Unit.PRICE):
        return IndicatorResult(_IDS["rsi"], (), None, Unit.PERCENT, defined=False, reason="incompatible_unit")
    numbers = [_number(item) for item in prices]
    if any(v is None for v in numbers):
        return IndicatorResult(_IDS["rsi"], (), None, Unit.PERCENT, defined=False, reason="missing_input")
    clean = [v or 0.0 for v in numbers]
    changes = [clean[i] - clean[i - 1] for i in range(1, len(clean))]
    gains = [max(c, 0.0) for c in changes]
    losses = [max(-c, 0.0) for c in changes]
    avg_gain = sum(gains[:window]) / window
    avg_loss = sum(losses[:window]) / window
    values: list[float | None] = [None] * window
    for index in range(window, len(changes)):
        avg_gain = (avg_gain * (window - 1) + gains[index]) / window
        avg_loss = (avg_loss * (window - 1) + losses[index]) / window
        if avg_loss == 0:
            rsi = 100.0 if avg_gain > 0 else 50.0
        else:
            rs = avg_gain / avg_loss
            rsi = 100 - 100 / (1 + rs)
        values.append(rsi)
    return IndicatorResult(_IDS["rsi"], tuple(values), values[-1], Unit.PERCENT)


__all__ = [
    "annualized_volatility",
    "cagr",
    "cumulative_return",
    "debt_to_equity",
    "gross_margin",
    "income_hhi",
    "income_source_share",
    "macd",
    "max_drawdown",
    "net_margin",
    "net_worth",
    "portfolio_expected_return",
    "price_change",
    "real_return",
    "revenue_growth",
    "roi",
    "rsi_wilder",
    "sharpe_ratio",
    "simple_return",
    "sma",
    "weekly_change",
]
