import pandas as pd
import pytest

from finance_lab.indicators import add_indicators
from finance_lab.market_data import latest_quotes, load_prices, synthetic_prices
from finance_lab.portfolio import max_sharpe_weights
from finance_lab.provenance import SourceKind, is_real_market_data
from finance_lab.reporting import SyntheticDataError, write_tearsheet


def _offline_dataset(symbols=("GLD", "SPY")):
    # Never touch the network in tests; force the synthetic fallback.
    return load_prices(symbols, allow_live=False, allow_cache=False)


def test_offline_pipeline() -> None:
    prices = synthetic_prices(["GLD", "SPY"], periods=120)

    indicators = add_indicators(prices)
    assert "GLD_rsi14" in indicators.columns
    assert "SPY_macd" in indicators.columns

    weights = max_sharpe_weights(prices)
    assert set(weights) == {"GLD", "SPY"}
    assert abs(sum(weights.values()) - 1.0) < 1e-6


def test_synthetic_dataset_is_labelled_on_every_row() -> None:
    dataset = _offline_dataset()

    assert dataset.kind is SourceKind.SYNTHETIC
    assert dataset.is_synthetic
    assert not dataset.is_real_market_data
    assert not is_real_market_data(dataset.kind)

    labeled = dataset.labeled_frame()
    assert set(labeled["source_kind"]) == {"synthetic"}
    assert set(labeled["source"]) == {"offline-generator"}
    assert "fetched_at" in labeled.columns
    assert labeled.index.name == "Date"


def test_quotes_carry_provenance_columns() -> None:
    rows = latest_quotes(["GLD", "SPY"], allow_live=False, allow_cache=False)

    assert len(rows) == 2
    for row in rows:
        assert row["source_kind"] == "synthetic"
        assert row["source"] == "offline-generator"
        assert row["fetched_at"]
        assert "note" in row


def test_report_refuses_synthetic_data() -> None:
    returns = synthetic_prices(["GLD"], periods=60)["GLD"].pct_change().dropna()

    with pytest.raises(SyntheticDataError):
        write_tearsheet(returns, name="must_not_exist", source_kind=SourceKind.SYNTHETIC)


def test_real_kinds_are_recognised() -> None:
    assert is_real_market_data(SourceKind.LIVE)
    assert is_real_market_data("cached")
    assert isinstance(pd.DataFrame(), pd.DataFrame)
