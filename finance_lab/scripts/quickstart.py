"""End-to-end demo: data -> indicators -> weights -> gold -> report.

Every written row carries a provenance label. Synthetic data is never mixed
with real market data and is excluded from performance reports.
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import pandas as pd

from finance_lab.config import OUTPUT_DIR, PORTFOLIO_SYMBOLS
from finance_lab.gold import gold_snapshot
from finance_lab.indicators import add_indicators
from finance_lab.market_data import latest_quotes, load_prices, save_prices
from finance_lab.portfolio import max_sharpe_weights
from finance_lab.reporting import write_tearsheet


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    symbols = list(PORTFOLIO_SYMBOLS)

    dataset = load_prices(symbols, period="2y")
    save_prices(dataset, "prices.csv")

    indicators = add_indicators(dataset.frame)
    indicators.to_csv(OUTPUT_DIR / "indicators.csv")

    weights = max_sharpe_weights(dataset.frame)
    pd.Series(weights, name="weight").to_csv(OUTPUT_DIR / "weights.csv")

    quotes = latest_quotes(symbols)
    pd.DataFrame(quotes).to_csv(OUTPUT_DIR / "quotes.csv", index=False)

    gold = gold_snapshot()
    pd.DataFrame(gold).to_csv(OUTPUT_DIR / "gold.csv", index=False)

    provenance = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "dataset": dataset.provenance(),
        "labels": ["live", "cached", "synthetic", "manual"],
        "policy": (
            "Synthetic rows are labelled and excluded from financial "
            "performance reports; they are not real market data."
        ),
    }
    (OUTPUT_DIR / "provenance.json").write_text(
        json.dumps(provenance, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    equal_weight_returns = dataset.frame.pct_change().dropna().mean(axis=1)
    try:
        report = write_tearsheet(
            equal_weight_returns, "equal_weight", source_kind=dataset.kind
        )
        report_note = str(report)
    except Exception as error:  # reporting is non-critical for the pipeline
        report_note = f"skipped ({type(error).__name__})"

    print("Saved outputs to:", OUTPUT_DIR)
    print("Source kind:", dataset.kind.value, "| source:", dataset.source)
    print("Provenance:", OUTPUT_DIR / "provenance.json")
    if not dataset.is_real_market_data:
        print(
            "WARNING: source_kind=synthetic. These are offline demo numbers, "
            "NOT real market prices; do not use them as financial evidence."
        )
        if dataset.note:
            print("Reason:", dataset.note)
    print("Weights:", weights)
    print("Gold snapshot (labelled):", gold)
    print("Tearsheet:", report_note)


if __name__ == "__main__":
    main()
