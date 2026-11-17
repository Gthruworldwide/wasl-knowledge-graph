from __future__ import annotations

import matplotlib

matplotlib.use("Agg")  # headless-friendly backend for HTML reports

import pandas as pd
import quantstats as qs

from .config import OUTPUT_DIR


def write_tearsheet(returns: pd.Series, name: str = "portfolio"):
    """Write a QuantStats HTML performance report under output/."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / f"{name}_tearsheet.html"
    qs.reports.html(returns, output=str(path), title=name)
    return path
