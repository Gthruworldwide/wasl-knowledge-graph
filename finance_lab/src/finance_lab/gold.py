from .config import GOLD_ETF, GOLD_FUTURES, SILVER_ETF
from .market_data import latest_quotes

# Yahoo does not serve XAUUSD=X in every region; GC=F and GLD are reliable.
GOLD_SYMBOLS = (GOLD_FUTURES, GOLD_ETF, SILVER_ETF)


def gold_snapshot() -> list[dict[str, object]]:
    """Spot, futures and ETF views of gold plus silver as a cross-check."""
    return latest_quotes(GOLD_SYMBOLS)
