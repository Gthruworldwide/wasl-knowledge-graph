"""Data provenance labels required by WASL_FINANCIAL_AI_SPEC.md.

Every persisted data row must state what it is: ``live``, ``cached``,
``synthetic`` or ``manual``. Synthetic data must never be presented as real
market data or used in a financial performance report.
"""

from __future__ import annotations

from enum import Enum


class SourceKind(str, Enum):
    LIVE = "live"
    CACHED = "cached"
    SYNTHETIC = "synthetic"
    MANUAL = "manual"


REAL_MARKET_KINDS = frozenset({SourceKind.LIVE, SourceKind.CACHED})


def kind_value(kind: SourceKind | str) -> str:
    """Return the plain string value, whether given an enum or a string."""
    return kind.value if isinstance(kind, SourceKind) else str(kind)


def is_real_market_data(kind: SourceKind | str) -> bool:
    return kind_value(kind) in {item.value for item in REAL_MARKET_KINDS}


__all__ = [
    "REAL_MARKET_KINDS",
    "SourceKind",
    "is_real_market_data",
    "kind_value",
]
