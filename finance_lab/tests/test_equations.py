from datetime import date

import pytest

from finance_lab.equations import (
    SPECS,
    SPEC_BY_ID,
    cagr,
    cumulative_return,
    debt_to_equity,
    get_spec,
    grade_answer,
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
    roi,
    rsi_wilder,
    sharpe_ratio,
    simple_return,
    sma,
    annualized_volatility,
    weekly_change,
)
from finance_lab.equations.catalog import EquationSpec
from finance_lab.provenance import SourceKind
from finance_lab.equations.types import MetricInput, Period, Unit


def mi(value, unit=Unit.CURRENCY, **kwargs) -> MetricInput:
    return MetricInput(value=value, unit=unit, **kwargs)


def _series(value, unit=Unit.RATIO, count=20) -> tuple[MetricInput, ...]:
    return tuple(mi(value, unit) for _ in range(count))


def test_catalog_is_complete() -> None:
    assert len(SPECS) == 21
    assert len(SPEC_BY_ID) == len(SPECS)
    for spec in SPECS:
        assert isinstance(spec, EquationSpec)
        assert spec.formula and spec.symbols and spec.inputs
        assert spec.edge_cases and spec.validity and spec.worked_example
        assert spec.reference.startswith("WASL_FINANCIAL_AI_SPEC.md")
        assert spec.version == "1.0.0"
        assert spec.expected_output is not None
        assert spec.tolerance >= 0
    with pytest.raises(KeyError):
        get_spec("does.not.exist")


def test_every_catalog_example_matches_deterministic_engine() -> None:
    p1 = Period("FY2025")
    week_now = Period("W2026-45", start=date(2026, 11, 9))
    week_prev = Period("W2026-44", start=date(2026, 11, 2))
    vectors = {
        "wealth.net_worth": net_worth(mi(120000), mi(45000)),
        "wealth.weekly_change_isoweek": weekly_change(
            mi(1100, period=week_now), mi(1000, period=week_prev)
        ),
        "wealth.income_source_share": income_source_share(mi(3000), mi(10000)),
        "wealth.income_source_hhi": income_hhi(
            (mi(0.5, Unit.RATIO), mi(0.3, Unit.RATIO), mi(0.2, Unit.RATIO))
        ),
        "business.revenue_growth": revenue_growth(
            mi(120, period=p1), mi(100, period=p1)
        ),
        "business.gross_margin": gross_margin(mi(200), mi(120)),
        "business.net_margin": net_margin(mi(30), mi(200)),
        "business.debt_to_equity": debt_to_equity(mi(80), mi(100)),
        "business.roi": roi(mi(130), mi(100)),
        "market.simple_return": simple_return(mi(110, Unit.PRICE), mi(100, Unit.PRICE)),
        "market.cumulative_return": cumulative_return(
            (mi(0.1, Unit.RATIO), mi(-0.05, Unit.RATIO), mi(0.2, Unit.RATIO))
        ),
        "market.cagr": cagr(
            mi(100, Unit.PRICE),
            mi(200, Unit.PRICE),
            date(2015, 1, 1),
            date(2025, 1, 1),
        ),
        "portfolio.expected_return": portfolio_expected_return(
            (mi(0.6, Unit.RATIO), mi(0.4, Unit.RATIO)),
            (mi(0.08, Unit.RATIO), mi(0.05, Unit.RATIO)),
        ),
        "portfolio.annualized_volatility": annualized_volatility(
            tuple(
                mi(0.01 if i % 2 == 0 else -0.01, Unit.RATIO) for i in range(20)
            )
        ),
        "portfolio.sharpe_ratio": sharpe_ratio(
            mi(0.10, Unit.RATIO), mi(0.02, Unit.RATIO), mi(0.20, Unit.RATIO)
        ),
        "portfolio.max_drawdown": max_drawdown(
            tuple(mi(v, Unit.PRICE) for v in (100, 120, 90, 110))
        ),
        "portfolio.real_return_after_inflation": real_return(
            mi(0.07, Unit.RATIO), mi(0.03, Unit.RATIO)
        ),
        "market.price_change": price_change(mi(105, Unit.PRICE), mi(100, Unit.PRICE)),
        "indicator.sma": sma(tuple(mi(v, Unit.PRICE) for v in (1, 2, 3, 4, 5)), 3),
        "indicator.macd": macd(_series(100, Unit.PRICE, 30)),
        "indicator.rsi_wilder": rsi_wilder(_series(100, Unit.PRICE, 16)),
    }

    assert set(vectors) == set(SPEC_BY_ID)
    for spec in SPECS:
        result = vectors[spec.id]
        actual = result.value if hasattr(result, "value") else result.last
        assert actual is not None, spec.id
        assert abs(actual - (spec.expected_output or 0)) <= spec.tolerance, (
            spec.id,
            actual,
            spec.expected_output,
        )


def test_undefined_instead_of_fabricated_zero() -> None:
    zero = net_margin(mi(30), mi(0))
    assert not zero.defined
    assert zero.reason == "zero_denominator"
    assert zero.value is None
    assert zero.display == "غير متاح"

    missing = net_worth(mi(None), mi(10))
    assert not missing.defined
    assert missing.reason == "missing_input"

    bad_cagr = cagr(mi(0, Unit.PRICE), mi(100, Unit.PRICE), date(2020, 1, 1), date(2025, 1, 1))
    assert bad_cagr.reason == "non_positive_value"


def test_currency_period_and_unit_guards() -> None:
    currency = net_worth(mi(100, currency="USD"), mi(50, currency="EUR"))
    assert currency.reason == "incompatible_currency"

    unit = net_worth(mi(100, Unit.PRICE), mi(50, Unit.CURRENCY))
    assert unit.reason == "incompatible_unit"

    non_consecutive = weekly_change(
        mi(1100, period=Period("W1", start=date(2026, 11, 9))),
        mi(1000, period=Period("W3", start=date(2026, 10, 26))),
    )
    assert non_consecutive.reason == "non_consecutive_iso_weeks"

    weights = portfolio_expected_return(
        (mi(0.7, Unit.RATIO), mi(0.4, Unit.RATIO)),
        (mi(0.08, Unit.RATIO), mi(0.05, Unit.RATIO)),
    )
    assert weights.reason == "invalid_weight_sum"

    short = annualized_volatility(_series(0.01, Unit.RATIO, 10))
    assert short.reason == "insufficient_observations"


def test_synthetic_and_real_inputs_are_never_mixed() -> None:
    live = mi(100, source_kind=SourceKind.LIVE, source="provider")
    synthetic = mi(50, source_kind=SourceKind.SYNTHETIC, source="offline-generator")
    result = net_worth(live, synthetic)

    assert not result.defined
    assert result.reason == "mixed_provenance"


def test_result_keeps_provenance_and_quality_flags() -> None:
    result = income_source_share(
        mi(3000, currency="USD", estimated=True, source="user"),
        mi(10000, currency="USD", source="user"),
    )
    assert result.qualifier == "estimated"
    assert result.currency == "USD"
    assert result.value == pytest.approx(30.0)


def test_training_uses_reviewed_reference_not_a_model() -> None:
    good = grade_answer("business.gross_margin", 40.0)
    assert good.correct
    assert good.reference == 40.0
    assert "محرك المعادلات الحتمي" in " ".join(good.steps)

    bad = grade_answer("business.gross_margin", 41.0)
    assert not bad.correct

    loose = grade_answer("business.gross_margin", 41.0, tolerance=2.0)
    assert loose.correct

    with pytest.raises(KeyError):
        grade_answer("unknown.id", 1.0)
