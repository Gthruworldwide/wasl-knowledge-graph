"""Print the reviewed equation catalog and demonstrate deterministic grading."""

import json
import sys
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from finance_lab.config import OUTPUT_DIR
from finance_lab.equations import SPECS, grade_answer, net_worth
from finance_lab.equations.types import MetricInput, Unit


def _serialize(item) -> object:
    if hasattr(item, "__iter__") and not isinstance(item, (str, dict)):
        return [_serialize(value) for value in item]
    if isinstance(item, dict):
        return {key: _serialize(value) for key, value in item.items()}
    if hasattr(item, "value") and hasattr(item, "name"):
        return item.value
    return item


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / "equations_catalog.json"
    path.write_text(
        json.dumps([_serialize(asdict(spec)) for spec in SPECS], indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    result = net_worth(MetricInput(120000, Unit.CURRENCY), MetricInput(45000, Unit.CURRENCY))
    graded = grade_answer("business.gross_margin", 40.0)

    print(f"Catalog: {len(SPECS)} reviewed equations -> {path}")
    print("net_worth example:", result.display, "| id:", result.id)
    print("training:", graded.note, "| reference:", graded.reference)


if __name__ == "__main__":
    main()
