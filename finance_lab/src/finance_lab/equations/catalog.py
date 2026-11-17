"""Reviewed equation catalog: ids, formulas, edge cases and numeric vectors."""

from __future__ import annotations

from dataclasses import dataclass

from .types import Unit

VERSION = "1.0.0"


@dataclass(frozen=True)
class InputSpec:
    name: str
    unit: Unit
    source: str
    frequency: str


@dataclass(frozen=True)
class EquationSpec:
    id: str
    name_ar: str
    name_en: str
    domain: str
    formula: str
    symbols: dict[str, str]
    inputs: tuple[InputSpec, ...]
    unit: Unit
    currency_policy: str
    validity: tuple[str, ...]
    edge_cases: tuple[str, ...]
    worked_example: str
    expected_output: float | None
    tolerance: float
    reference: str
    version: str = VERSION


def _spec(
    id: str,
    name_ar: str,
    name_en: str,
    domain: str,
    formula: str,
    symbols: dict[str, str],
    inputs: tuple[tuple[str, Unit, str, str], ...],
    unit: Unit,
    currency_policy: str,
    validity: tuple[str, ...],
    edge_cases: tuple[str, ...],
    worked_example: str,
    expected_output: float | None,
    reference: str,
    tolerance: float = 1e-6,
) -> EquationSpec:
    return EquationSpec(
        id=id,
        name_ar=name_ar,
        name_en=name_en,
        domain=domain,
        formula=formula,
        symbols=symbols,
        inputs=tuple(InputSpec(*item) for item in inputs),
        unit=unit,
        currency_policy=currency_policy,
        validity=validity,
        edge_cases=edge_cases,
        worked_example=worked_example,
        expected_output=expected_output,
        tolerance=tolerance,
        reference=reference,
    )


COMMON_EDGE = (
    "quantities or dates missing -> 'غير متاح' with a reason",
    "currency or period mismatch -> 'غير متاح'",
    "synthetic input never mixed with live/cached input",
)

SPECS: tuple[EquationSpec, ...] = (
    _spec(
        "wealth.net_worth", "صافي الثروة", "Net worth", "wealth",
        "assets - liabilities",
        {"assets": "إجمالي الأصول", "liabilities": "إجمالي الالتزامات"},
        (("assets", Unit.CURRENCY, "user-entered balance sheet", "manual"),
         ("liabilities", Unit.CURRENCY, "user-entered balance sheet", "manual")),
        Unit.CURRENCY, "both inputs must share one ISO currency",
        ("values must be finite",), COMMON_EDGE,
        "أصول 120000 والتزامات 45000 => 75000", 75000.0,
        "WASL_FINANCIAL_AI_SPEC.md: wealth section",
    ),
    _spec(
        "wealth.weekly_change_isoweek", "التغير الأسبوعي", "Weekly change", "wealth",
        "((V_this - V_prev_iso_week) / V_prev_iso_week) * 100",
        {"V_this": "لقطة هذا الأسبوع", "V_prev_iso_week": "لقطة أسبوع ISO السابق مباشرة"},
        (("current", Unit.CURRENCY, "dated snapshot", "weekly"),
         ("previous", Unit.CURRENCY, "dated snapshot", "weekly")),
        Unit.PERCENT, "both inputs must share one ISO currency",
        ("periods must be consecutive ISO weeks (7 days apart)",),
        COMMON_EDGE + ("non-consecutive weeks -> undefined",),
        "1100 مقابل 1000 في الأسبوع السابق مباشرة => 10%", 10.0,
        "WASL_FINANCIAL_AI_SPEC.md: wealth section",
    ),
    _spec(
        "wealth.income_source_share", "حصة مصدر الدخل", "Income source share", "wealth",
        "(source / sum(known income sources)) * 100",
        {"source": "قيمة المصدر", "sum": "مجموع المصادر المعروفة"},
        (("source", Unit.CURRENCY, "user-entered income", "manual"),
         ("total", Unit.CURRENCY, "catalogued sources", "manual")),
        Unit.PERCENT, "single ISO currency",
        ("total > 0", "estimated inputs are qualified, not facts"), COMMON_EDGE,
        "3000 من 10000 => 30%", 30.0,
        "WASL_FINANCIAL_AI_SPEC.md: wealth section",
    ),
    _spec(
        "wealth.income_source_hhi", "تركيز مصادر الدخل", "Income concentration HHI", "wealth",
        "sum(share_i^2) where share_i is a decimal fraction",
        {"share_i": "حصة المصدر ككسر عشري"},
        (("shares", Unit.RATIO, "derived from income shares", "manual"),),
        Unit.INDEX, "currency-free index",
        ("shares must sum to 1 within 1e-6",), COMMON_EDGE,
        "0.5, 0.3, 0.2 => 0.38", 0.38,
        "WASL_FINANCIAL_AI_SPEC.md: wealth section",
    ),
    _spec(
        "business.revenue_growth", "نمو الإيرادات", "Revenue growth", "business",
        "((current / prior) - 1) * 100",
        {"current": "إيرادات الفترة الحالية", "prior": "إيرادات فترة المقارنة"},
        (("current", Unit.CURRENCY, "financial statement", "period"),
         ("prior", Unit.CURRENCY, "financial statement", "period")),
        Unit.PERCENT, "single ISO currency and matching period labels",
        ("prior != 0",), COMMON_EDGE,
        "120 مقابل 100 => 20%", 20.0,
        "WASL_FINANCIAL_AI_SPEC.md: business section",
    ),
    _spec(
        "business.gross_margin", "هامش الربح الإجمالي", "Gross margin", "business",
        "((revenue - cogs) / revenue) * 100",
        {"revenue": "الإيرادات", "cogs": "تكلفة البضاعة المباعة"},
        (("revenue", Unit.CURRENCY, "financial statement", "period"),
         ("cogs", Unit.CURRENCY, "financial statement", "period")),
        Unit.PERCENT, "single ISO currency", ("revenue != 0",), COMMON_EDGE,
        "إيرادات 200 وتكلفة 120 => 40%", 40.0,
        "WASL_FINANCIAL_AI_SPEC.md: business section",
    ),
    _spec(
        "business.net_margin", "هامش صافي الربح", "Net margin", "business",
        "(net_income / revenue) * 100",
        {"net_income": "صافي الربح", "revenue": "الإيرادات"},
        (("net_income", Unit.CURRENCY, "financial statement", "period"),
         ("revenue", Unit.CURRENCY, "financial statement", "period")),
        Unit.PERCENT, "single ISO currency", ("revenue != 0",), COMMON_EDGE,
        "30 من 200 => 15%", 15.0,
        "WASL_FINANCIAL_AI_SPEC.md: business section",
    ),
    _spec(
        "business.debt_to_equity", "الدين إلى حقوق الملكية", "Debt to equity", "business",
        "total_debt / equity",
        {"total_debt": "إجمالي الدين", "equity": "حقوق الملكية"},
        (("debt", Unit.CURRENCY, "balance sheet", "period"),
         ("equity", Unit.CURRENCY, "balance sheet", "period")),
        Unit.RATIO, "single ISO currency", ("equity != 0",), COMMON_EDGE,
        "80 مقابل 100 => 0.8", 0.8,
        "WASL_FINANCIAL_AI_SPEC.md: business section",
    ),
    _spec(
        "business.roi", "العائد على الاستثمار", "Return on investment", "business",
        "((final_value - cost) / cost) * 100",
        {"final_value": "القيمة النهائية", "cost": "التكلفة"},
        (("final_value", Unit.CURRENCY, "valuation", "manual"),
         ("cost", Unit.CURRENCY, "valuation", "manual")),
        Unit.PERCENT, "single ISO currency", ("cost != 0",), COMMON_EDGE,
        "130 مقابل تكلفة 100 => 30%", 30.0,
        "WASL_FINANCIAL_AI_SPEC.md: business section",
    ),
    _spec(
        "market.simple_return", "العائد البسيط", "Simple return", "market",
        "P_t / P_(t-1) - 1",
        {"P_t": "الإغلاق المعدل الحالي", "P_(t-1)": "الإغلاق المعدل السابق"},
        (("current", Unit.PRICE, "labelled price series", "daily"),
         ("previous", Unit.PRICE, "labelled price series", "daily")),
        Unit.RATIO, "same instrument, market and currency",
        ("P_(t-1) > 0",), COMMON_EDGE,
        "110 مقابل 100 => 0.1", 0.1,
        "WASL_FINANCIAL_AI_SPEC.md: markets section",
    ),
    _spec(
        "market.cumulative_return", "العائد التراكمي", "Cumulative return", "market",
        "product(1 + r_t) - 1",
        {"r_t": "عائد الفترة", "product": "ضرب كل العوائد"},
        (("returns", Unit.RATIO, "derived from price series", "daily"),),
        Unit.RATIO, "currency-free", ("r_t > -1 for every t",), COMMON_EDGE,
        "0.1, -0.05, 0.2 => 0.254", 0.254,
        "WASL_FINANCIAL_AI_SPEC.md: markets section",
    ),
    _spec(
        "market.cagr", "معدل النمو السنوي المركب", "CAGR", "market",
        "(V_end / V_start)^(1 / n) - 1 where n = actual years",
        {"V_end": "القيمة النهائية", "V_start": "القيمة الابتدائية", "n": "سنوات فعلية"},
        (("start_value", Unit.PRICE, "labelled price series", "manual"),
         ("end_value", Unit.PRICE, "labelled price series", "manual")),
        Unit.RATIO, "same instrument and currency",
        ("both values > 0", "end date after start date"), COMMON_EDGE,
        "100 إلى 200 خلال 2015-01-01..2025-01-01 => حوالي 0.0718", 0.0718,
        "WASL_FINANCIAL_AI_SPEC.md: markets section", tolerance=1e-3,
    ),
    _spec(
        "portfolio.expected_return", "العائد المتوقع للمحفظة", "Portfolio expected return", "portfolio",
        "sum(w_i * mu_i)",
        {"w_i": "وزن الأصل", "mu_i": "العائد المتوقع للأصل"},
        (("weights", Unit.RATIO, "portfolio model", "manual"),
         ("expected_returns", Unit.RATIO, "research assumption", "manual")),
        Unit.RATIO, "currency-free; weights must sum to 1",
        ("sum(w_i) = 1 within 1e-6",), COMMON_EDGE + ("invalid weight sum -> undefined",),
        "0.6*0.08 + 0.4*0.05 => 0.068", 0.068,
        "WASL_FINANCIAL_AI_SPEC.md: markets section",
    ),
    _spec(
        "portfolio.annualized_volatility", "التقلب السنوي", "Annualized volatility", "portfolio",
        "stdev(daily returns) * sqrt(252)",
        {"stdev": "الانحراف المعياري للعينة", "252": "عدد أيام التداول"},
        (("daily_returns", Unit.RATIO, "labelled price series", "daily"),),
        Unit.RATIO, "currency-free",
        ("at least 20 observations",), COMMON_EDGE + ("historical estimate, not a forecast",),
        "عشرون عائدا بالتناوب +0.01/-0.01 => حوالي 0.1629", 0.1629,
        "WASL_FINANCIAL_AI_SPEC.md: markets section", tolerance=1e-3,
    ),
    _spec(
        "portfolio.sharpe_ratio", "نسبة شارب", "Sharpe ratio", "portfolio",
        "(annual_return - risk_free_rate) / annual_volatility",
        {"annual_return": "العائد السنوي", "risk_free_rate": "معدل خالٍ من المخاطر", "annual_volatility": "التقلب السنوي"},
        (("annual_return", Unit.RATIO, "research assumption", "annual"),
         ("risk_free_rate", Unit.RATIO, "published rate", "annual"),
         ("annual_volatility", Unit.RATIO, "historical estimate", "annual")),
        Unit.RATIO, "same currency, period and annualisation method",
        ("volatility > 0",), COMMON_EDGE + ("inconsistent annualisation -> undefined",),
        "(0.10 - 0.02) / 0.20 => 0.4", 0.4,
        "WASL_FINANCIAL_AI_SPEC.md: markets section",
    ),
    _spec(
        "portfolio.max_drawdown", "السحب الأقصى", "Maximum drawdown", "portfolio",
        "min(V_t / max(V_0..V_t) - 1)",
        {"V_t": "قيمة المحفظة", "max": "أعلى قيمة سابقة"},
        (("values", Unit.PRICE, "labelled portfolio series", "daily"),),
        Unit.RATIO, "single currency", ("at least 2 observations",), COMMON_EDGE,
        "100, 120, 90, 110 => -0.25", -0.25,
        "WASL_FINANCIAL_AI_SPEC.md: markets section",
    ),
    _spec(
        "portfolio.real_return_after_inflation", "العائد الحقيقي بعد التضخم", "Real return after inflation", "portfolio",
        "((1 + nominal) / (1 + inflation)) - 1",
        {"nominal": "العائد الاسمي", "inflation": "معدل التضخم"},
        (("nominal", Unit.RATIO, "computed return", "annual"),
         ("inflation", Unit.RATIO, "IMF/FMP CPI context", "annual")),
        Unit.RATIO, "currency-free; both rates must cover the same period",
        ("inflation > -1",), COMMON_EDGE + ("simple subtraction is only a labelled approximation",),
        "(1.07 / 1.03) - 1 => حوالي 0.038835", 0.038835,
        "WASL_FINANCIAL_AI_SPEC.md: markets section", tolerance=1e-6,
    ),
    _spec(
        "market.price_change", "تغير السعر", "Price change", "market",
        "((current / previous) - 1) * 100",
        {"current": "السعر الحالي", "previous": "السعر السابق"},
        (("current", Unit.PRICE, "labelled quote", "tick"),
         ("previous", Unit.PRICE, "labelled quote", "tick")),
        Unit.PERCENT, "same instrument, market, currency and timestamp convention",
        ("previous > 0",), COMMON_EDGE,
        "105 مقابل 100 => 5%", 5.0,
        "WASL_FINANCIAL_AI_SPEC.md: markets section",
    ),
    _spec(
        "indicator.sma", "المتوسط المتحرك البسيط", "Simple moving average", "indicator",
        "mean of last n prices",
        {"n": "نافذة المتوسط"},
        (("prices", Unit.PRICE, "labelled price series", "daily"),),
        Unit.PRICE, "single instrument and currency",
        ("1 <= n <= number of observations",), COMMON_EDGE,
        "أسعار 1..5 بنافذة 3 => 4", 4.0,
        "WASL_FINANCIAL_AI_SPEC.md: markets section",
    ),
    _spec(
        "indicator.macd", "MACD", "MACD", "indicator",
        "EMA(12) - EMA(26), signal = EMA(9) of MACD",
        {"EMA": "المتوسط المتحرك الأسي"},
        (("prices", Unit.PRICE, "labelled price series", "daily"),),
        Unit.PRICE, "single instrument and currency",
        ("at least 26 observations",), COMMON_EDGE,
        "سلسلة ثابتة عند 100 => MACD = 0", 0.0,
        "WASL_FINANCIAL_AI_SPEC.md: markets section",
    ),
    _spec(
        "indicator.rsi_wilder", "RSI (Wilder)", "RSI (Wilder)", "indicator",
        "100 - 100 / (1 + avg_gain / avg_loss)",
        {"avg_gain": "متوسط المكاسب", "avg_loss": "متوسط الخسائر"},
        (("prices", Unit.PRICE, "labelled price series", "daily"),),
        Unit.PERCENT, "single instrument and currency",
        ("at least window + 1 observations",),
        COMMON_EDGE + ("avg_loss = 0 and avg_gain = 0 -> 50",),
        "سلسلة ثابتة عند 100 => RSI = 50", 50.0,
        "WASL_FINANCIAL_AI_SPEC.md: markets section",
    ),
)

SPEC_BY_ID: dict[str, EquationSpec] = {item.id: item for item in SPECS}


def get_spec(equation_id: str) -> EquationSpec:
    try:
        return SPEC_BY_ID[equation_id]
    except KeyError as error:
        raise KeyError(f"Unknown equation id: {equation_id}") from error


__all__ = ["SPECS", "SPEC_BY_ID", "EquationSpec", "InputSpec", "VERSION", "get_spec"]
