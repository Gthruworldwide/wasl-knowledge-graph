from __future__ import annotations

import pandas as pd
from pypfopt import EfficientFrontier


def max_sharpe_weights(prices: pd.DataFrame, frequency: int = 252) -> dict[str, float]:
    """Mean-variance max-Sharpe weights using PyPortfolioOpt."""
    returns = prices.dropna().pct_change().dropna()
    mu = returns.mean() * frequency
    covariance = returns.cov() * frequency
    frontier = EfficientFrontier(mu, covariance)
    frontier.max_sharpe()
    return frontier.clean_weights()
