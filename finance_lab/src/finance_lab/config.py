from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = ROOT / "output"

# Gold / commodities
GOLD_SPOT = "XAUUSD=X"
GOLD_FUTURES = "GC=F"
GOLD_ETF = "GLD"
SILVER_ETF = "SLV"

# Simple multi-asset portfolio used by the quickstart
PORTFOLIO_SYMBOLS = ("GLD", "SPY", "TLT", "VNQ")
