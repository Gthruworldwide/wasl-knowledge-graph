from __future__ import annotations

import pandas as pd
from ta.momentum import RSIIndicator
from ta.trend import MACD, SMAIndicator


def add_indicators(close: pd.DataFrame) -> pd.DataFrame:
    """Add RSI(14), SMA(20) and MACD for every price column."""
    result = close.copy()
    for column in close.columns:
        series = close[column].dropna()
        result[f"{column}_rsi14"] = RSIIndicator(series, window=14).rsi()
        result[f"{column}_sma20"] = SMAIndicator(series, window=20).sma_indicator()
        result[f"{column}_macd"] = MACD(series).macd()
    return result
