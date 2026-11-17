import 'dart:math' as math;

import 'equation_catalog.dart';
import 'equation_models.dart';

/// Deterministic equation engine. No AI model computes or invents numbers.
class EquationEngine {
  const EquationEngine._();

  static const version = '1.0.0';

  static double? _number(MetricInput? item) {
    final value = item?.value;
    if (value == null || !value.isFinite) return null;
    return value;
  }

  static bool _currenciesOk(List<MetricInput> items) {
    final present = <String>{
      for (final item in items)
        if (item.currency != null) item.currency!,
    };
    if (present.length > 1) return false;
    if (present.isEmpty) return true;
    return items.every((item) => item.currency != null);
  }

  static bool _periodsOk(List<MetricInput> items) {
    if (items.every((item) => item.period == null)) return true;
    if (items.any((item) => item.period == null)) return false;
    return items.map((item) => item.period!.label).toSet().length == 1;
  }

  static bool _unitsOk(List<MetricInput> items, EquationUnit unit) =>
      items.isNotEmpty && items.every((item) => item.unit == unit);

  static _CommonData? _common(List<MetricInput> items) {
    final real = items.map((item) => isRealMarketData(item.sourceKind)).toList();
    if (real.any((value) => value) && !real.every((value) => value)) return null;
    String? currency;
    EquationPeriod? period;
    String? source;
    for (final item in items) {
      currency ??= item.currency;
      period ??= item.period;
      source ??= item.source;
    }
    return _CommonData(currency, period, source, items.first.sourceKind);
  }

  static MetricResult _finish(
    String id,
    EquationUnit unit,
    List<MetricInput> items,
    double? value, {
    String? reason,
    String? qualifier,
  }) {
    final common = _common(items);
    if (common == null) {
      // Mixed real/synthetic provenance: return an explicit undefined result.
      // Do not call _bad() here — that would recurse back into _finish().
      return MetricResult(
        id: id,
        value: null,
        unit: unit,
        defined: false,
        reason: 'mixed_provenance',
        sourceKind: items.first.sourceKind,
      );
    }
    return MetricResult(
      id: id,
      value: value,
      unit: unit,
      currency: common.currency,
      period: common.period,
      defined: reason == null && value != null,
      reason: reason,
      qualifier: qualifier,
      sourceKind: common.kind,
    );
  }

  static MetricResult _bad(
    String id,
    EquationUnit unit,
    List<MetricInput> items,
    String reason,
  ) =>
      _finish(id, unit, items, null, reason: reason);

  static MetricResult netWorth(MetricInput assets, MetricInput liabilities) {
    final items = [assets, liabilities];
    final a = _number(assets);
    final l = _number(liabilities);
    if (a == null || l == null) return _bad('wealth.net_worth', EquationUnit.currency, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.currency)) {
      return _bad('wealth.net_worth', EquationUnit.currency, items, 'incompatible_unit');
    }
    if (!_currenciesOk(items)) {
      return _bad('wealth.net_worth', EquationUnit.currency, items, 'incompatible_currency');
    }
    return _finish('wealth.net_worth', EquationUnit.currency, items, a - l);
  }

  static MetricResult weeklyChange(MetricInput current, MetricInput previous) {
    final items = [current, previous];
    const unit = EquationUnit.percent;
    final c = _number(current);
    final p = _number(previous);
    if (c == null || p == null) return _bad('wealth.weekly_change_isoweek', unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.currency) || !_currenciesOk(items)) {
      return _bad('wealth.weekly_change_isoweek', unit, items, 'incompatible_input');
    }
    final startNow = current.period?.start;
    final startPrev = previous.period?.start;
    if (startNow == null || startPrev == null) {
      return _bad('wealth.weekly_change_isoweek', unit, items, 'missing_period');
    }
    if (startNow.difference(startPrev).inDays != 7) {
      return _bad('wealth.weekly_change_isoweek', unit, items, 'non_consecutive_iso_weeks');
    }
    if (p == 0) return _bad('wealth.weekly_change_isoweek', unit, items, 'zero_denominator');
    return _finish('wealth.weekly_change_isoweek', unit, items, (c - p) / p * 100);
  }

  static MetricResult incomeShare(MetricInput source, MetricInput total) {
    final items = [source, total];
    final s = _number(source);
    final t = _number(total);
    if (s == null || t == null) return _bad('wealth.income_source_share', EquationUnit.percent, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.currency) || !_currenciesOk(items)) {
      return _bad('wealth.income_source_share', EquationUnit.percent, items, 'incompatible_input');
    }
    if (t <= 0) return _bad('wealth.income_source_share', EquationUnit.percent, items, 'zero_denominator');
    return _finish(
      'wealth.income_source_share',
      EquationUnit.percent,
      items,
      s / t * 100,
      qualifier: (source.estimated || total.estimated) ? 'estimated' : null,
    );
  }

  static MetricResult incomeHhi(List<MetricInput> shares) {
    const unit = EquationUnit.indexValue;
    const id = 'wealth.income_source_hhi';
    if (shares.isEmpty) return _bad(id, unit, shares, 'missing_input');
    if (!_unitsOk(shares, EquationUnit.ratio)) return _bad(id, unit, shares, 'incompatible_unit');
    final values = shares.map(_number).toList();
    if (values.any((value) => value == null)) return _bad(id, unit, shares, 'missing_input');
    final sum = values.fold<double>(0, (total, value) => total + value!);
    if ((sum - 1).abs() > 1e-6) return _bad(id, unit, shares, 'invalid_share_sum');
    return _finish(
      id,
      unit,
      shares,
      values.fold<double>(0, (total, value) {
        final v = value!;
        return total + v * v;
      }),
    );
  }

  static MetricResult revenueGrowth(MetricInput current, MetricInput prior) {
    final items = [current, prior];
    const unit = EquationUnit.percent;
    const id = 'business.revenue_growth';
    final c = _number(current);
    final p = _number(prior);
    if (c == null || p == null) return _bad(id, unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.currency) || !_currenciesOk(items)) return _bad(id, unit, items, 'incompatible_input');
    if (!_periodsOk(items)) return _bad(id, unit, items, 'incompatible_period');
    if (p == 0) return _bad(id, unit, items, 'zero_denominator');
    return _finish(id, unit, items, (c / p - 1) * 100);
  }

  static MetricResult grossMargin(MetricInput revenue, MetricInput cogs) {
    final items = [revenue, cogs];
    const unit = EquationUnit.percent;
    const id = 'business.gross_margin';
    final r = _number(revenue);
    final c = _number(cogs);
    if (r == null || c == null) return _bad(id, unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.currency) || !_currenciesOk(items)) return _bad(id, unit, items, 'incompatible_input');
    if (r == 0) return _bad(id, unit, items, 'zero_denominator');
    return _finish(id, unit, items, (r - c) / r * 100);
  }

  static MetricResult netMargin(MetricInput netIncome, MetricInput revenue) {
    final items = [netIncome, revenue];
    const unit = EquationUnit.percent;
    const id = 'business.net_margin';
    final n = _number(netIncome);
    final r = _number(revenue);
    if (n == null || r == null) return _bad(id, unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.currency) || !_currenciesOk(items)) return _bad(id, unit, items, 'incompatible_input');
    if (r == 0) return _bad(id, unit, items, 'zero_denominator');
    return _finish(id, unit, items, n / r * 100);
  }

  static MetricResult debtToEquity(MetricInput debt, MetricInput equity) {
    final items = [debt, equity];
    const unit = EquationUnit.ratio;
    const id = 'business.debt_to_equity';
    final d = _number(debt);
    final e = _number(equity);
    if (d == null || e == null) return _bad(id, unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.currency) || !_currenciesOk(items)) return _bad(id, unit, items, 'incompatible_input');
    if (e == 0) return _bad(id, unit, items, 'zero_denominator');
    return _finish(id, unit, items, d / e);
  }

  static MetricResult roi(MetricInput finalValue, MetricInput cost) {
    final items = [finalValue, cost];
    const unit = EquationUnit.percent;
    const id = 'business.roi';
    final f = _number(finalValue);
    final c = _number(cost);
    if (f == null || c == null) return _bad(id, unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.currency) || !_currenciesOk(items)) return _bad(id, unit, items, 'incompatible_input');
    if (c == 0) return _bad(id, unit, items, 'zero_denominator');
    return _finish(id, unit, items, (f - c) / c * 100);
  }

  static MetricResult simpleReturn(MetricInput current, MetricInput previous) {
    final items = [current, previous];
    const unit = EquationUnit.ratio;
    const id = 'market.simple_return';
    final c = _number(current);
    final p = _number(previous);
    if (c == null || p == null) return _bad(id, unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.price) || !_currenciesOk(items)) return _bad(id, unit, items, 'incompatible_input');
    if (p <= 0) return _bad(id, unit, items, 'non_positive_value');
    return _finish(id, unit, items, c / p - 1);
  }

  static MetricResult cumulativeReturn(List<MetricInput> returns) {
    const unit = EquationUnit.ratio;
    const id = 'market.cumulative_return';
    if (returns.isEmpty) return _bad(id, unit, returns, 'insufficient_observations');
    if (!_unitsOk(returns, EquationUnit.ratio)) return _bad(id, unit, returns, 'incompatible_unit');
    final values = returns.map(_number).toList();
    if (values.any((value) => value == null)) return _bad(id, unit, returns, 'missing_input');
    if (values.any((value) => value! <= -1)) return _bad(id, unit, returns, 'invalid_return');
    var growth = 1.0;
    for (final value in values) {
      growth *= 1 + value!;
    }
    return _finish(id, unit, returns, growth - 1);
  }

  static MetricResult cagr(
    MetricInput startValue,
    MetricInput endValue,
    DateTime start,
    DateTime end,
  ) {
    final items = [startValue, endValue];
    const unit = EquationUnit.ratio;
    const id = 'market.cagr';
    final s = _number(startValue);
    final e = _number(endValue);
    if (s == null || e == null) return _bad(id, unit, items, 'missing_input');
    if (startValue.unit != endValue.unit || !_currenciesOk(items)) return _bad(id, unit, items, 'incompatible_input');
    if (s <= 0 || e <= 0) return _bad(id, unit, items, 'non_positive_value');
    final days = end.difference(start).inDays;
    if (days <= 0) return _bad(id, unit, items, 'invalid_period');
    final years = days / 365.25;
    return _finish(id, unit, items, math.pow(e / s, 1 / years).toDouble() - 1);
  }

  static MetricResult portfolioReturn(
    List<MetricInput> weights,
    List<MetricInput> expectedReturns,
  ) {
    final items = [...weights, ...expectedReturns];
    const unit = EquationUnit.ratio;
    const id = 'portfolio.expected_return';
    if (weights.isEmpty || weights.length != expectedReturns.length) {
      return _bad(id, unit, items, 'invalid_weight_vector');
    }
    if (!_unitsOk(weights, EquationUnit.ratio) ||
        !_unitsOk(expectedReturns, EquationUnit.ratio)) {
      return _bad(id, unit, items, 'incompatible_unit');
    }
    final w = weights.map(_number).toList();
    final mu = expectedReturns.map(_number).toList();
    if ([...w, ...mu].any((value) => value == null)) return _bad(id, unit, items, 'missing_input');
    final weightSum = w.fold<double>(0, (total, value) => total + value!);
    if ((weightSum - 1).abs() > 1e-6) return _bad(id, unit, items, 'invalid_weight_sum');
    var result = 0.0;
    for (var i = 0; i < w.length; i++) {
      result += w[i]! * mu[i]!;
    }
    return _finish(id, unit, items, result);
  }

  static MetricResult annualizedVolatility(List<MetricInput> dailyReturns) {
    const unit = EquationUnit.ratio;
    const id = 'portfolio.annualized_volatility';
    if (dailyReturns.length < 20) return _bad(id, unit, dailyReturns, 'insufficient_observations');
    if (!_unitsOk(dailyReturns, EquationUnit.ratio)) return _bad(id, unit, dailyReturns, 'incompatible_unit');
    final values = dailyReturns.map(_number).toList();
    if (values.any((value) => value == null)) return _bad(id, unit, dailyReturns, 'missing_input');
    final mean = values.fold<double>(0, (total, value) => total + value!) / values.length;
    final variance = values.fold<double>(
      0,
      (total, value) => total + math.pow(value! - mean, 2),
    ) / (values.length - 1);
    return _finish(id, unit, dailyReturns, math.sqrt(variance) * math.sqrt(252));
  }

  static MetricResult sharpeRatio(
    MetricInput annualReturn,
    MetricInput riskFree,
    MetricInput annualVolatility,
  ) {
    final items = [annualReturn, riskFree, annualVolatility];
    const unit = EquationUnit.ratio;
    const id = 'portfolio.sharpe_ratio';
    final r = _number(annualReturn);
    final f = _number(riskFree);
    final v = _number(annualVolatility);
    if (r == null || f == null || v == null) return _bad(id, unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.ratio)) return _bad(id, unit, items, 'incompatible_unit');
    if (v <= 0) return _bad(id, unit, items, 'zero_denominator');
    return _finish(id, unit, items, (r - f) / v);
  }

  static MetricResult maxDrawdown(List<MetricInput> values) {
    const unit = EquationUnit.ratio;
    const id = 'portfolio.max_drawdown';
    if (values.length < 2) return _bad(id, unit, values, 'insufficient_observations');
    if (!_unitsOk(values, EquationUnit.price)) return _bad(id, unit, values, 'incompatible_unit');
    final numbers = values.map(_number).toList();
    if (numbers.any((value) => value == null)) return _bad(id, unit, values, 'missing_input');
    var peak = numbers.first!;
    var worst = 0.0;
    for (final value in numbers) {
      peak = math.max(peak, value!);
      if (peak > 0) worst = math.min(worst, value / peak - 1);
    }
    return _finish(id, unit, values, worst);
  }

  static MetricResult realReturn(MetricInput nominal, MetricInput inflation) {
    final items = [nominal, inflation];
    const unit = EquationUnit.ratio;
    const id = 'portfolio.real_return_after_inflation';
    final n = _number(nominal);
    final i = _number(inflation);
    if (n == null || i == null) return _bad(id, unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.ratio)) return _bad(id, unit, items, 'incompatible_unit');
    if (i <= -1) return _bad(id, unit, items, 'invalid_inflation_rate');
    return _finish(id, unit, items, (1 + n) / (1 + i) - 1);
  }

  static MetricResult priceChange(MetricInput current, MetricInput previous) {
    final items = [current, previous];
    const unit = EquationUnit.percent;
    const id = 'market.price_change';
    final c = _number(current);
    final p = _number(previous);
    if (c == null || p == null) return _bad(id, unit, items, 'missing_input');
    if (!_unitsOk(items, EquationUnit.price) || !_currenciesOk(items)) return _bad(id, unit, items, 'incompatible_input');
    if (p <= 0) return _bad(id, unit, items, 'non_positive_value');
    return _finish(id, unit, items, (c / p - 1) * 100);
  }

  static MetricResult computeById(
    String id,
    List<MetricInput> inputs, {
    DateTime? start,
    DateTime? end,
    int window = 20,
  }) {
    switch (id) {
      case 'wealth.net_worth':
        return netWorth(inputs[0], inputs[1]);
      case 'wealth.weekly_change_isoweek':
        return weeklyChange(inputs[0], inputs[1]);
      case 'wealth.income_source_share':
        return incomeShare(inputs[0], inputs[1]);
      case 'wealth.income_source_hhi':
        return incomeHhi(inputs);
      case 'business.revenue_growth':
        return revenueGrowth(inputs[0], inputs[1]);
      case 'business.gross_margin':
        return grossMargin(inputs[0], inputs[1]);
      case 'business.net_margin':
        return netMargin(inputs[0], inputs[1]);
      case 'business.debt_to_equity':
        return debtToEquity(inputs[0], inputs[1]);
      case 'business.roi':
        return roi(inputs[0], inputs[1]);
      case 'market.simple_return':
        return simpleReturn(inputs[0], inputs[1]);
      case 'market.cumulative_return':
        return cumulativeReturn(inputs);
      case 'market.cagr':
        if (start == null || end == null) {
          return _bad(id, EquationUnit.ratio, inputs, 'missing_period');
        }
        return cagr(inputs[0], inputs[1], start, end);
      case 'portfolio.expected_return':
        final half = inputs.length ~/ 2;
        return portfolioReturn(inputs.sublist(0, half), inputs.sublist(half));
      case 'portfolio.annualized_volatility':
        return annualizedVolatility(inputs);
      case 'portfolio.sharpe_ratio':
        return sharpeRatio(inputs[0], inputs[1], inputs[2]);
      case 'portfolio.max_drawdown':
        return maxDrawdown(inputs);
      case 'portfolio.real_return_after_inflation':
        return realReturn(inputs[0], inputs[1]);
      case 'market.price_change':
        return priceChange(inputs[0], inputs[1]);
      default:
        throw ArgumentError('Unknown equation id: $id');
    }
  }

  /// Grades against the deterministic engine result, never an AI-generated number.
  static GradedAnswer grade({
    required String id,
    required List<MetricInput> inputs,
    required double learnerValue,
    double? tolerance,
    DateTime? start,
    DateTime? end,
  }) {
    final spec = equationSpecById(id);
    final result = computeById(id, inputs, start: start, end: end);
    if (!result.defined || result.value == null) {
      throw StateError('Cannot grade an undefined equation: ${result.reason}');
    }
    final usedTolerance = tolerance ?? spec.tolerance;
    final reference = result.value!;
    final correct = (learnerValue - reference).abs() <= usedTolerance;
    return GradedAnswer(
      reference: reference,
      learner: learnerValue,
      tolerance: usedTolerance,
      correct: correct,
      steps: [
        'المعادلة: ${spec.formula}',
        'المثال: ${spec.workedExample}',
        'الناتج المرجعي: ${roundTo(reference, 6)} (${spec.unit.wireName})',
        'حُسب بمحرك المعادلات الحتمي، لا بنموذج ذكاء اصطناعي.',
        'السماحية: ±$usedTolerance',
      ],
      note: correct ? 'إجابة صحيحة ضمن السماحية' : 'راجع خطوات الحل',
    );
  }
}

class _CommonData {
  final String? currency;
  final EquationPeriod? period;
  final String? source;
  final EquationSourceKind kind;

  const _CommonData(this.currency, this.period, this.source, this.kind);
}
