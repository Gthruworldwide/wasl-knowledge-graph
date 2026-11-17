"""Deterministic, typed financial equation catalog for Wasl.

No AI model computes or invents numbers here. Every formula has a stable id,
declared units/currencies/periods, explicit edge cases, a worked example and an
independent numeric test vector.
"""

from .catalog import SPEC_BY_ID, SPECS, EquationSpec, get_spec
from .engine import (
    cumulative_return,
    cagr,
    debt_to_equity,
    gross_margin,
    income_hhi,
    income_source_share,
    macd,
    max_drawdown,
    net_margin,
    net_worth,
    portfolio_expected_return,
    price_change,
    real_return,
    revenue_growth,
    rsi_wilder,
    sharpe_ratio,
    simple_return,
    sma,
    annualized_volatility,
    weekly_change,
    roi,
)
from .training import GradedAnswer, grade_answer
from .types import (
    IndicatorResult,
    MetricInput,
    MetricResult,
    Period,
    Unit,
    undefined,
)

__all__ = [
    "SPECS",
    "SPEC_BY_ID",
    "EquationSpec",
    "GradedAnswer",
    "IndicatorResult",
    "MetricInput",
    "MetricResult",
    "Period",
    "Unit",
    "annualized_volatility",
    "cagr",
    "cumulative_return",
    "debt_to_equity",
    "get_spec",
    "grade_answer",
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
    "undefined",
    "weekly_change",
]
