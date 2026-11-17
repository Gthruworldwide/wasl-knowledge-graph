"""Equation tutoring: the catalog computes the reference answer, never an LLM."""

from __future__ import annotations

import math
from dataclasses import dataclass

from .catalog import get_spec


@dataclass(frozen=True)
class GradedAnswer:
    spec_id: str
    reference: float
    learner: float
    tolerance: float
    correct: bool
    steps: tuple[str, ...]
    note: str


def grade_answer(
    spec_id: str, learner_value: float, tolerance: float | None = None
) -> GradedAnswer:
    """Compare a learner's number with the catalog's declared reference.

    The AI may phrase the question and explanation, but the final number comes
    from ``EquationSpec.expected_output`` which was reviewed and test-verified.
    """
    spec = get_spec(spec_id)
    if spec.expected_output is None:
        raise ValueError(f"Equation {spec_id} has no reviewed reference answer")
    reference = float(spec.expected_output)
    if not math.isfinite(reference):
        raise ValueError(f"Equation {spec_id} has an invalid reference answer")
    learner = float(learner_value)
    if not math.isfinite(learner):
        raise ValueError("Learner answer must be a finite number")
    used_tolerance = spec.tolerance if tolerance is None else float(tolerance)
    if used_tolerance < 0:
        raise ValueError("Tolerance must be non-negative")

    steps = (
        f"المعادلة: {spec.formula}",
        f"المثال المعلّم: {spec.worked_example}",
        f"الناتج المرجعي: {reference:.6g} ({spec.unit.value})",
        "تم اشتقاق الناتج بمحرك المعادلات الحتمي، وليس بنموذج ذكاء اصطناعي.",
        f"السماحية المعلنة: ±{used_tolerance:g}",
    )
    note = (
        "إجابة صحيحة ضمن السماحية"
        if abs(learner - reference) <= used_tolerance
        else "الحاجة إلى مراجعة الخطوات"
    )
    return GradedAnswer(
        spec_id=spec_id,
        reference=reference,
        learner=learner,
        tolerance=used_tolerance,
        correct=abs(learner - reference) <= used_tolerance,
        steps=steps,
        note=note,
    )


__all__ = ["GradedAnswer", "grade_answer"]
