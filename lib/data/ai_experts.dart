import 'ai_models.dart';

class AiExpertConfig {
  final AiExpertKind kind;
  final String labelAr;
  final String labelEn;
  final String instructionAr;
  final List<AiToolName> allowedTools;
  final List<String> prohibitionsAr;

  const AiExpertConfig({
    required this.kind,
    required this.labelAr,
    required this.labelEn,
    required this.instructionAr,
    required this.allowedTools,
    required this.prohibitionsAr,
  });
}

const _commonProhibitions = <String>[
  'لا تحسب أرقامًا بنفسك؛ النتيجة تأتي من محرك المعادلات الحتمي فقط.',
  'لا تقدّم توصية شراء أو بيع أو تشخيصًا ماليًا أو شخصيًا.',
  'لا تصدر فتوى أو ادعاءً شرعيًا.',
  'إذا غاب الدليل أو تعذّر الحساب، قل «غير متاح» واذكر السبب.',
  'ميّز دائمًا بين قيمة مصدرية ونتيجة محسوبة وتقدير وشرح مولّد.',
];

const aiExpertConfigs = <AiExpertKind, AiExpertConfig>{
  AiExpertKind.equationTutor: AiExpertConfig(
    kind: AiExpertKind.equationTutor,
    labelAr: 'معلّم المعادلات',
    labelEn: 'Equation tutor',
    instructionAr:
        'اشرح المعادلة المراجعة من الكتالوج، اعرض مثالًا معلّمًا، وأنشئ تمرينًا '
        'وتحقق من إجابة المتعلم. الصيغة والرموز من الكتالوج فقط، والإجابة '
        'النهائية من محرك المعادلات. لا تستخدم بيانات سوق حقيقية في التمرين.',
    allowedTools: [AiToolName.getEquationSpec, AiToolName.computeEquation],
    prohibitionsAr: _commonProhibitions,
  ),
  AiExpertKind.metricExplainer: AiExpertConfig(
    kind: AiExpertKind.metricExplainer,
    labelAr: 'شارح المقاييس',
    labelEn: 'Metric explainer',
    instructionAr:
        'اشرح نتيجة محسوبة أو قيمة مصدرية مع وحدتها وعملتها وفترتها ومصدرها. '
        'اذكر إن كانت النتيجة تقديرًا تاريخيًا وليست تنبؤًا، ولا تخلط قيمة '
        'الشركة السوقية بإيراداتها ولا دخل الشخص بصافي ثروته.',
    allowedTools: [
      AiToolName.getEquationSpec,
      AiToolName.computeEquation,
      AiToolName.latestObservation,
      AiToolName.searchKnowledge,
    ],
    prohibitionsAr: _commonProhibitions,
  ),
  AiExpertKind.dataQualityReviewer: AiExpertConfig(
    kind: AiExpertKind.dataQualityReviewer,
    labelAr: 'مراجع جودة البيانات',
    labelEn: 'Data quality reviewer',
    instructionAr:
        'راجع وسوم المصدر والوحدة والعملة والفترة. ارفض خلط live أو cached مع '
        'synthetic، ولا تعرض بيانات اصطناعية بوصفها أسعار سوق أو ثروة حقيقية.',
    allowedTools: [
      AiToolName.getEquationSpec,
      AiToolName.searchKnowledge,
      AiToolName.latestObservation,
    ],
    prohibitionsAr: _commonProhibitions,
  ),
};

AiExpertConfig expertConfig(AiExpertKind kind) => aiExpertConfigs[kind]!;
