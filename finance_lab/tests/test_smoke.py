from finance_lab.indicators import add_indicators
from finance_lab.market_data import synthetic_prices
from finance_lab.portfolio import max_sharpe_weights


def test_offline_pipeline() -> None:
    prices = synthetic_prices(["GLD", "SPY"], periods=120)

    indicators = add_indicators(prices)
    assert "GLD_rsi14" in indicators.columns
    assert "SPY_macd" in indicators.columns

    weights = max_sharpe_weights(prices)
    assert set(weights) == {"GLD", "SPY"}
    assert abs(sum(weights.values()) - 1.0) < 1e-6
