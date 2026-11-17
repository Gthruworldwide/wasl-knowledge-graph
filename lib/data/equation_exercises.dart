import 'equation_models.dart';

/// A deterministic training exercise. Numbers are fabricated demo values,
/// never real market observations, and the UI says so explicitly.
class EquationExercise {
  final String specId;
  final String promptAr;
  final String promptEn;
  final String givenAr;
  final String givenEn;
  final List<MetricInput> inputs;
  final DateTime? start;
  final DateTime? end;

  const EquationExercise({
    required this.specId,
    required this.promptAr,
    required this.promptEn,
    required this.givenAr,
    required this.givenEn,
    required this.inputs,
    this.start,
    this.end,
  });

  String prompt(bool isArabic) => isArabic ? promptAr : promptEn;
  String given(bool isArabic) => isArabic ? givenAr : givenEn;
}

final _weekNow = EquationPeriod(label: 'W2026-45', start: DateTime(2026, 11, 9));
final _weekPrev = EquationPeriod(label: 'W2026-44', start: DateTime(2026, 11, 2));
const _fy = EquationPeriod(label: 'FY2025');

/// One exercise per scalar equation. Each set of inputs reproduces the
/// reviewed `expectedOutput` in [equationCatalog] when run through the engine.
final equationExercises = <EquationExercise>[
  EquationExercise(
    specId: 'wealth.net_worth',
    promptAr: 'احسب صافي الثروة.',
    promptEn: 'Compute net worth.',
    givenAr: 'الأصول 120,000 والالتزامات 45,000 دولار.',
    givenEn: 'Assets 120,000 and liabilities 45,000 USD.',
    inputs: [
      MetricInput(value: 120000, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 45000, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'wealth.weekly_change_isoweek',
    promptAr: 'احسب التغير الأسبوعي بين أسبوعي ISO متتاليين.',
    promptEn: 'Compute the weekly change between consecutive ISO weeks.',
    givenAr: 'هذا الأسبوع 1,100 والأسبوع السابق مباشرة 1,000 دولار.',
    givenEn: 'This week 1,100 and the immediately previous week 1,000 USD.',
    inputs: [
      MetricInput(value: 1100, unit: EquationUnit.currency, currency: 'USD', period: _weekNow, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 1000, unit: EquationUnit.currency, currency: 'USD', period: _weekPrev, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'wealth.income_source_share',
    promptAr: 'احسب حصة مصدر الدخل.',
    promptEn: 'Compute the income source share.',
    givenAr: 'المصدر 3,000 من إجمالي 10,000 دولار.',
    givenEn: 'Source 3,000 out of total 10,000 USD.',
    inputs: [
      MetricInput(value: 3000, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 10000, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'wealth.income_source_hhi',
    promptAr: 'احسب مؤشر تركيز مصادر الدخل (HHI).',
    promptEn: 'Compute the income concentration HHI.',
    givenAr: 'الحصص ككسر عشري: 0.5 و0.3 و0.2.',
    givenEn: 'Shares as decimal fractions: 0.5, 0.3 and 0.2.',
    inputs: [
      MetricInput(value: 0.5, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 0.3, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 0.2, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'business.revenue_growth',
    promptAr: 'احسب نمو الإيرادات.',
    promptEn: 'Compute revenue growth.',
    givenAr: 'إيرادات FY2025 = 120 وإيرادات FY2024 = 100 دولار.',
    givenEn: 'FY2025 revenue = 120 and FY2024 revenue = 100 USD.',
    inputs: [
      MetricInput(value: 120, unit: EquationUnit.currency, currency: 'USD', period: _fy, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 100, unit: EquationUnit.currency, currency: 'USD', period: _fy, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'business.gross_margin',
    promptAr: 'احسب هامش الربح الإجمالي.',
    promptEn: 'Compute gross margin.',
    givenAr: 'الإيرادات 200 وتكلفة البضاعة المباعة 120 دولار.',
    givenEn: 'Revenue 200 and cost of goods sold 120 USD.',
    inputs: [
      MetricInput(value: 200, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 120, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'business.net_margin',
    promptAr: 'احسب هامش صافي الربح.',
    promptEn: 'Compute net margin.',
    givenAr: 'صافي الربح 30 والإيرادات 200 دولار.',
    givenEn: 'Net income 30 and revenue 200 USD.',
    inputs: [
      MetricInput(value: 30, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 200, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'business.debt_to_equity',
    promptAr: 'احسب نسبة الدين إلى حقوق الملكية.',
    promptEn: 'Compute debt to equity.',
    givenAr: 'إجمالي الدين 80 وحقوق الملكية 100 دولار.',
    givenEn: 'Total debt 80 and equity 100 USD.',
    inputs: [
      MetricInput(value: 80, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 100, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'business.roi',
    promptAr: 'احسب العائد على الاستثمار.',
    promptEn: 'Compute return on investment.',
    givenAr: 'القيمة النهائية 130 والتكلفة 100 دولار.',
    givenEn: 'Final value 130 and cost 100 USD.',
    inputs: [
      MetricInput(value: 130, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 100, unit: EquationUnit.currency, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'market.simple_return',
    promptAr: 'احسب العائد البسيط للسهم.',
    promptEn: 'Compute the simple return of a stock.',
    givenAr: 'السعر الحالي 110 والسعر السابق 100 دولار.',
    givenEn: 'Current price 110 and previous price 100 USD.',
    inputs: [
      MetricInput(value: 110, unit: EquationUnit.price, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 100, unit: EquationUnit.price, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'market.cumulative_return',
    promptAr: 'احسب العائد التراكمي لثلاث فترات.',
    promptEn: 'Compute the cumulative return over three periods.',
    givenAr: 'عوائد الفترات: 0.1 و-0.05 و0.2.',
    givenEn: 'Period returns: 0.1, -0.05 and 0.2.',
    inputs: [
      MetricInput(value: 0.1, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: -0.05, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 0.2, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'market.cagr',
    promptAr: 'احسب معدل النمو السنوي المركب.',
    promptEn: 'Compute the compound annual growth rate.',
    givenAr: 'من 100 إلى 200 بين 2015-01-01 و2025-01-01.',
    givenEn: 'From 100 to 200 between 2015-01-01 and 2025-01-01.',
    inputs: [
      MetricInput(value: 100, unit: EquationUnit.price, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 200, unit: EquationUnit.price, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
    start: DateTime(2015, 1, 1),
    end: DateTime(2025, 1, 1),
  ),
  EquationExercise(
    specId: 'portfolio.expected_return',
    promptAr: 'احسب العائد المتوقع للمحفظة.',
    promptEn: 'Compute the expected portfolio return.',
    givenAr: 'الأوزان 0.6 و0.4 والعوائد المتوقعة 0.08 و0.05.',
    givenEn: 'Weights 0.6 and 0.4 with expected returns 0.08 and 0.05.',
    inputs: [
      MetricInput(value: 0.6, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 0.4, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 0.08, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 0.05, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'portfolio.annualized_volatility',
    promptAr: 'احسب التقلب السنوي لعشرين عائدا يوميا.',
    promptEn: 'Compute annualized volatility for twenty daily returns.',
    givenAr: 'عشرون عائدا بالتناوب +0.01 و-0.01.',
    givenEn: 'Twenty alternating returns of +0.01 and -0.01.',
    inputs: List.generate(
      20,
      (i) => MetricInput(
        value: i.isEven ? 0.01 : -0.01,
        unit: EquationUnit.ratio,
        sourceKind: EquationSourceKind.synthetic,
        source: 'demo-exercise',
      ),
    ),
  ),
  EquationExercise(
    specId: 'portfolio.sharpe_ratio',
    promptAr: 'احسب نسبة شارب.',
    promptEn: 'Compute the Sharpe ratio.',
    givenAr: 'العائد السنوي 0.10 والمعدل الخالي من المخاطر 0.02 والتقلب 0.20.',
    givenEn: 'Annual return 0.10, risk-free rate 0.02 and volatility 0.20.',
    inputs: [
      MetricInput(value: 0.10, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 0.02, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 0.20, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'portfolio.max_drawdown',
    promptAr: 'احسب السحب الأقصى لسلسلة قيمة المحفظة.',
    promptEn: 'Compute the maximum drawdown of a portfolio value series.',
    givenAr: 'القيم: 100 و120 و90 و110.',
    givenEn: 'Values: 100, 120, 90, 110.',
    inputs: [
      MetricInput(value: 100, unit: EquationUnit.price, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 120, unit: EquationUnit.price, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 90, unit: EquationUnit.price, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 110, unit: EquationUnit.price, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'portfolio.real_return_after_inflation',
    promptAr: 'احسب العائد الحقيقي بعد التضخم.',
    promptEn: 'Compute the real return after inflation.',
    givenAr: 'العائد الاسمي 0.07 والتضخم 0.03.',
    givenEn: 'Nominal return 0.07 and inflation 0.03.',
    inputs: [
      MetricInput(value: 0.07, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 0.03, unit: EquationUnit.ratio, sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
  EquationExercise(
    specId: 'market.price_change',
    promptAr: 'احسب التغير النسبي في السعر.',
    promptEn: 'Compute the percentage price change.',
    givenAr: 'السعر الحالي 105 والسعر السابق 100 دولار.',
    givenEn: 'Current price 105 and previous price 100 USD.',
    inputs: [
      MetricInput(value: 105, unit: EquationUnit.price, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
      MetricInput(value: 100, unit: EquationUnit.price, currency: 'USD', sourceKind: EquationSourceKind.synthetic, source: 'demo-exercise'),
    ],
  ),
];
