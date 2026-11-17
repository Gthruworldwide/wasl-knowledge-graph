import 'package:flutter/material.dart';

import '../data/equation_catalog.dart';
import '../data/equation_engine.dart';
import '../data/equation_exercises.dart';
import '../data/equation_models.dart';

/// In-app equation tutoring. The reference number always comes from the
/// deterministic [EquationEngine]; no AI model is involved in grading.
class EquationTrainingPage extends StatefulWidget {
  const EquationTrainingPage({super.key});

  @override
  State<EquationTrainingPage> createState() => _EquationTrainingPageState();
}

class _EquationTrainingPageState extends State<EquationTrainingPage> {
  final _answerController = TextEditingController();
  int _index = 0;
  GradedAnswer? _grade;
  String? _error;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  EquationExercise get _exercise =>
      equationExercises[_index % equationExercises.length];

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _nextExercise() {
    setState(() {
      _index = (_index + 1) % equationExercises.length;
      _answerController.clear();
      _grade = null;
      _error = null;
    });
  }

  void _submit() {
    final parsed = double.tryParse(_answerController.text.trim().replaceAll(',', '.'));
    if (parsed == null) {
      setState(() => _error = _isArabic
          ? 'أدخل رقما صحيحا.'
          : 'Enter a valid number.');
      return;
    }
    final exercise = _exercise;
    try {
      final grade = EquationEngine.grade(
        id: exercise.specId,
        inputs: exercise.inputs,
        learnerValue: parsed,
        start: exercise.start,
        end: exercise.end,
      );
      setState(() {
        _grade = grade;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic;
    final exercise = _exercise;
    final spec = equationSpecById(exercise.specId);
    final name = isArabic ? spec.nameAr : spec.nameEn;

    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'تدريب المعادلات' : 'Equation training'),
        actions: [
          IconButton(
            tooltip: isArabic ? 'تمرين جديد' : 'New exercise',
            onPressed: _nextExercise,
            icon: const Icon(Icons.skip_next),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DemoBanner(isArabic: isArabic),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${spec.domain} · ${spec.version} · ${equationCatalog.length}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    SelectableText(
                      spec.formula,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'مثال معلّم (مرجع الكتالوج)' : 'Worked example (catalog reference)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(spec.workedExample),
                    const SizedBox(height: 6),
                    Text(
                      '${isArabic ? 'الناتج' : 'Result'}: ${roundTo(spec.expectedOutput, 6)} ${spec.unit.wireName}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'التمرين' : 'Exercise',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(exercise.prompt(isArabic)),
                    const SizedBox(height: 8),
                    Text(exercise.given(isArabic)),
                    const SizedBox(height: 8),
                    Text(
                      isArabic
                        ? 'مصدر الأرقام: تجريبي (synthetic) — ليس بيانات سوق.'
                        : 'Numbers source: synthetic demo — not market data.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answerController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: isArabic ? 'إجابتك' : 'Your answer',
                hintText: isArabic ? 'رقم' : 'number',
                suffixText: spec.unit.wireName,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check),
                  label: Text(isArabic ? 'تحقق' : 'Check'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _nextExercise,
                  icon: const Icon(Icons.skip_next),
                  label: Text(isArabic ? 'تمرين جديد' : 'New exercise'),
                ),
              ],
            ),
            if (_grade != null) ...[
              const SizedBox(height: 16),
              _FeedbackCard(grade: _grade!, isArabic: isArabic),
            ],
          ],
        ),
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isArabic
          ? 'وضع تجريبي (demo): الأرقام مصطنعة لأغراض التدريب فقط، وليست أسعار سوق حقيقية ولا تُستخدم في أي تقرير.'
          : 'Demo mode: numbers are fabricated for practice only, are not real market prices, and are never used in reports.',
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.grade, required this.isArabic});

  final GradedAnswer grade;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final color = grade.correct
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(grade.correct ? Icons.check_circle : Icons.error_outline, color: color),
                const SizedBox(width: 8),
                Text(grade.note, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${isArabic ? 'المرجع' : 'Reference'}: ${roundTo(grade.reference, 6)} '
              '· ${isArabic ? 'إجابتك' : 'Yours'}: ${roundTo(grade.learner, 6)} '
              '· ±${grade.tolerance}',
            ),
            const SizedBox(height: 10),
            ...grade.steps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $step'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
