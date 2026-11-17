from __future__ import annotations

import matplotlib

matplotlib.use("Agg")  # headless-friendly backend for HTML reports

import pandas as pd
import quantstats as qs

from .config import OUTPUT_DIR
from .provenance import SourceKind, is_real_market_data


class SyntheticDataError(ValueError):
    """Raised when a report would present synthetic data as real performance."""


def write_tearsheet(
    returns: pd.Series,
    name: str = "portfolio",
    *,
    source_kind: SourceKind | str | None = None,
):
    """Write a QuantStats HTML performance report under output/.

    Synthetic data is refused: a performance report must not look like a real
    financial result (WASL_FINANCIAL_AI_SPEC.md, data-quality section).
    """
    if source_kind is not None and not is_real_market_data(source_kind):
        raise SyntheticDataError(
            f"Refusing to write '{name}' tearsheet from "
            f"'{source_kind}' data; use live or cached real market data."
        )
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / f"{name}_tearsheet.html"
    qs.reports.html(returns, output=str(path), title=name)
    return path
