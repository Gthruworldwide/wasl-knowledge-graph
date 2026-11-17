"""Typed values and results for the Wasl equation catalog."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from enum import Enum

from ..provenance import SourceKind


class Unit(str, Enum):
    CURRENCY = "currency"
    PERCENT = "percent"
    RATIO = "ratio"
    PRICE = "price"
    INDEX = "index"
    COUNT = "count"


@dataclass(frozen=True)
class Period:
    """Reporting period; ``start`` is used for ISO-week ordering checks."""

    label: str
    start: date | None = None
    end: date | None = None
    frequency: str | None = None  # daily | weekly | monthly | annual


@dataclass(frozen=True)
class MetricInput:
    """One dated, sourced input. ``estimated`` never becomes a confirmed fact."""

    value: float | None
    unit: Unit
    currency: str | None = None
    period: Period | None = None
    as_of: date | None = None
    source: str | None = None
    source_kind: SourceKind = SourceKind.MANUAL
    estimated: bool = False
    instrument: str | None = None
    market: str | None = None


@dataclass(frozen=True)
class MetricResult:
    """A metric value plus everything needed to reproduce and qualify it."""

    id: str
    value: float | None
    unit: Unit
    currency: str | None
    period: Period | None
    as_of: date | None
    source: str | None
    source_kind: SourceKind
    defined: bool
    reason: str | None = None
    qualifier: str | None = None
    inputs: tuple[str, ...] = ()
    version: str = "1.0.0"

    @property
    def display(self) -> str:
        if not self.defined or self.value is None:
            return "غير متاح"
        suffix = "%" if self.unit is Unit.PERCENT else ""
        return f"{self.value:.6g}{suffix}"


@dataclass(frozen=True)
class IndicatorResult:
    """Series-valued indicator (SMA / MACD / RSI)."""

    id: str
    values: tuple[float | None, ...]
    last: float | None
    unit: Unit
    signal: tuple[float | None, ...] = ()
    defined: bool = True
    reason: str | None = None
    source_kind: SourceKind = SourceKind.MANUAL
    version: str = "1.0.0"


def undefined(
    id: str,
    reason: str,
    *,
    unit: Unit,
    currency: str | None = None,
    period: Period | None = None,
    source_kind: SourceKind = SourceKind.MANUAL,
    inputs: tuple[str, ...] = (),
    version: str = "1.0.0",
) -> MetricResult:
    """Build the explicit 'not available' result required by the spec."""
    return MetricResult(
        id=id,
        value=None,
        unit=unit,
        currency=currency,
        period=period,
        as_of=None,
        source=None,
        source_kind=source_kind,
        defined=False,
        reason=reason,
        inputs=inputs,
        version=version,
    )


__all__ = [
    "IndicatorResult",
    "MetricInput",
    "MetricResult",
    "Period",
    "Unit",
    "undefined",
]
