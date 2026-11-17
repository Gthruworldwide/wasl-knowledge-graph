"""End-to-end demo: data -> indicators -> weights -> gold -> report."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import pandas as pd

from finance_lab.config import OUTPUT_DIR, PORTFOLIO_SYMBOLS
from finance_lab.gold import gold_snapshot
from finance_lab.indicators import add_indicators
from finance_lab.market_data import download_prices, latest_quotes
from finance_lab.portfolio import max_sharpe_weights
from finance_lab.reporting import write_tearsheet


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    symbols = list(PORTFOLIO_SYMBOLS)

    prices = download_prices(symbols, period="2y")
    prices.to_csv(OUTPUT_DIR / "prices.csv")

    indicators = add_indicators(prices)
    indicators.to_csv(OUTPUT_DIR / "indicators.csv")

    weights = max_sharpe_weights(prices)
    pd.Series(weights, name="weight").to_csv(OUTPUT_DIR / "weights.csv")

    quotes = latest_quotes(symbols)
    pd.DataFrame(quotes).to_csv(OUTPUT_DIR / "quotes.csv", index=False)

    gold = gold_snapshot()
    pd.DataFrame(gold).to_csv(OUTPUT_DIR / "gold.csv", index=False)

    equal_weight_returns = prices.pct_change().dropna().mean(axis=1)
    try:
        report = write_tearsheet(equal_weight_returns, "equal_weight")
        report_note = str(report)
    except Exception as error:  # reporting is non-critical for the pipeline
        report_note = f"skipped ({type(error).__name__})"

    print("Saved outputs to:", OUTPUT_DIR)
    print("Weights:", weights)
    print("Gold snapshot:", gold)
    print("Tearsheet:", report_note)


if __name__ == "__main__":
    main()
