import 'package:flutter/material.dart';

import '../data/week_identifier.dart';

class WeeklyUpdateDraft {
  const WeeklyUpdateDraft({
    required this.weekIdentifier,
    required this.currencyUnit,
    this.totalNetWorth,
    this.summaryNote,
  });

  final String weekIdentifier;
  final String currencyUnit;
  final double? totalNetWorth;
  final String? summaryNote;
}

Future<WeeklyUpdateDraft?> showWeeklyUpdateSheet(
  BuildContext context, {
  required bool isArabic,
  Set<String> existingWeeks = const {},
}) => showModalBottomSheet<WeeklyUpdateDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      _WeeklyUpdateSheet(isArabic: isArabic, existingWeeks: existingWeeks),
);

class _WeeklyUpdateSheet extends StatefulWidget {
  const _WeeklyUpdateSheet({
    required this.isArabic,
    required this.existingWeeks,
  });

  final bool isArabic;
  final Set<String> existingWeeks;

  @override
  State<_WeeklyUpdateSheet> createState() => _WeeklyUpdateSheetState();
}

class _WeeklyUpdateSheetState extends State<_WeeklyUpdateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _week = TextEditingController(text: currentIsoWeekIdentifier());
  final _worth = TextEditingController();
  final _note = TextEditingController();
  String _currencyUnit = 'USD_M';
  bool _needsContent = false;

  @override
  void dispose() {
    _week.dispose();
    _worth.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final worth = _numberOrNull(_worth.text);
    final note = _nullable(_note.text);
    if (worth == null && note == null) {
      setState(() => _needsContent = true);
      return;
    }
    Navigator.pop(
      context,
      WeeklyUpdateDraft(
        weekIdentifier: _week.text.trim(),
        currencyUnit: _currencyUnit,
        totalNetWorth: worth,
        summaryNote: note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = widget.isArabic;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isArabic ? 'تحديث أسبوعي جديد' : 'New weekly update',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  isArabic
                      ? 'أضف تقديرًا أسبوعيًا أو ملاحظة دون تغيير الأسابيع السابقة.'
                      : 'Add a weekly estimate or note without changing earlier weeks.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextFormField(
                    controller: _week,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: isArabic
                          ? 'معرّف الأسبوع (YYYY-Www)'
                          : 'Week identifier (YYYY-Www)',
                      hintText: '2026-W47',
                    ),
                    validator: (value) {
                      final normalized = value?.trim() ?? '';
                      if (normalized.isEmpty) {
                        return isArabic ? 'هذا الحقل مطلوب' : 'Required';
                      }
                      try {
                        isoWeekMonday(normalized);
                      } on FormatException {
                        return isArabic
                            ? 'استخدم صيغة YYYY-Www، مثل 2026-W47'
                            : 'Use YYYY-Www, for example 2026-W47';
                      }
                      if (widget.existingWeeks.contains(normalized)) {
                        return isArabic
                            ? 'يوجد تحديث لهذا الأسبوع بالفعل.'
                            : 'A weekly update already exists for this week.';
                      }
                      return null;
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _worth,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: isArabic ? 'صافي الثروة' : 'Net worth',
                          ),
                          onChanged: (_) {
                            if (_needsContent) {
                              setState(() => _needsContent = false);
                            }
                          },
                          validator: (value) {
                            final normalized = value?.trim() ?? '';
                            if (normalized.isEmpty) return null;
                            final parsed = double.tryParse(normalized);
                            if (parsed == null ||
                                !parsed.isFinite ||
                                parsed < 0) {
                              return isArabic
                                  ? 'أدخل رقمًا صالحًا'
                                  : 'Enter a valid number';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _currencyUnit,
                          decoration: InputDecoration(
                            labelText: isArabic ? 'الوحدة' : 'Unit',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'USD_M',
                              child: Text('USD_M'),
                            ),
                            DropdownMenuItem(
                              value: 'USD_B',
                              child: Text('USD_B'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _currencyUnit = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: _note,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: isArabic
                          ? 'ملاحظة أسبوعية (اختياري)'
                          : 'Weekly note (optional)',
                    ),
                    onChanged: (_) {
                      if (_needsContent) {
                        setState(() => _needsContent = false);
                      }
                    },
                  ),
                ),
                if (_needsContent)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      isArabic
                          ? 'أدخل صافي الثروة أو ملاحظة واحدة على الأقل.'
                          : 'Enter a net worth or a note.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _save,
                  child: Text(isArabic ? 'حفظ التحديث' : 'Save update'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _nullable(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

double? _numberOrNull(String value) =>
    value.trim().isEmpty ? null : double.tryParse(value.trim());
