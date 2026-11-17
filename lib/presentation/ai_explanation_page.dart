import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/ai_consent.dart';
import '../data/ai_experts.dart';
import '../data/ai_grounding.dart';
import '../data/ai_models.dart';
import '../data/equation_catalog.dart';
import '../data/equation_exercises.dart';

class AiExplanationPage extends StatefulWidget {
  const AiExplanationPage({super.key});

  @override
  State<AiExplanationPage> createState() => _AiExplanationPageState();
}

class _AiExplanationPageState extends State<AiExplanationPage> {
  final _questionController = TextEditingController();
  final _grounding = const AiGroundingEngine();
  final _consent = AiConsentManager();

  AiExpertKind _expert = AiExpertKind.equationTutor;
  String _equationId = equationCatalog.first.id;
  GroundedResponse? _response;
  String? _status;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  void _explain() {
    final exercise = equationExercises.firstWhere(
      (item) => item.specId == _equationId,
    );
    final response = switch (_expert) {
      AiExpertKind.equationTutor => _grounding.explainEquation(
        equationId: exercise.specId,
        inputs: exercise.inputs,
        start: exercise.start,
        end: exercise.end,
      ),
      AiExpertKind.metricExplainer => _grounding.explainMetric(
        equationId: exercise.specId,
        inputs: exercise.inputs,
        start: exercise.start,
        end: exercise.end,
      ),
      AiExpertKind.dataQualityReviewer => _grounding.reviewDataQuality(
        inputs: exercise.inputs,
      ),
    };
    setState(() {
      _response = response;
      _status = null;
    });
  }

  Future<void> _reviewHosted() async {
    final response = _response;
    if (response == null) {
      setState(() => _status = _isArabic
          ? 'أنتج شرحًا محليًا أولاً.'
          : 'Produce a local explanation first.');
      return;
    }
    final payload = response.toPayload(question: _questionController.text.trim());
    final preview = _consent.preview(payload);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isArabic ? 'ما الذي سيُرسل؟' : 'What would be sent?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isArabic
                    ? 'لن يُرسل أي شيء قبل موافقتك. هذه هي الحمولة المسموح بها فقط:'
                    : 'Nothing is sent before you agree. This is the entire allowlisted payload:',
              ),
              const SizedBox(height: 8),
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(preview.payload.toJson()),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              if (preview.redacted.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${_isArabic ? 'تم حذف' : 'Redacted'}: ${preview.redacted.join(', ')}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_isArabic ? 'موافقة' : 'Approve'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    _consent.grantConsent();
    try {
      await _consent.sendToHosted(payload);
    } on AiHostedDisabled {
      if (!mounted) return;
      setState(() => _status = _isArabic
          ? 'النقل إلى نموذج مستضاف غير مُفعّل؛ مراجعة الخصوصية والترخيص مطلوبة أولاً.'
          : 'Hosted transfer is disabled; privacy and license review must come first.');
    } on AiConsentRequired {
      if (!mounted) return;
      setState(() => _status = _isArabic
          ? 'الموافقة مطلوبة قبل أي إرسال.'
          : 'Consent is required before any transfer.');
    }
  }

  void _clearSession() {
    _consent.revokeConsent();
    setState(() => _status = _isArabic
        ? 'تم إلغاء الموافقة وإزالة بيانات الجلسة.'
        : 'Consent revoked and session data cleared.');
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic;
    final response = _response;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'الشرح الموثّق' : 'Grounded explanation'),
        actions: [
          IconButton(
            tooltip: isArabic ? 'إزالة بيانات الجلسة' : 'Clear session data',
            onPressed: _clearSession,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isArabic
                    ? 'الوضع المحلي هو الافتراضي: لا يُرسل أي شيء إلى نموذج مستضاف قبل موافقة صريحة، ولا تُحفظ بيانات الجلسة.'
                    : 'Local mode is the default: nothing is sent to a hosted model before explicit consent, and session data is not persisted.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AiExpertKind>(
              initialValue: _expert,
              decoration: InputDecoration(
                labelText: isArabic ? 'الوظيفة' : 'Function',
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final kind in AiExpertKind.values)
                  DropdownMenuItem(value: kind, child: Text(kind.label(isArabic))),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _expert = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _equationId,
              decoration: InputDecoration(
                labelText: isArabic ? 'المعادلة' : 'Equation',
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final spec in equationCatalog)
                  DropdownMenuItem(
                    value: spec.id,
                    child: Text(isArabic ? spec.nameAr : spec.nameEn),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _equationId = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _questionController,
              decoration: InputDecoration(
                labelText: isArabic ? 'سؤالك (اختياري)' : 'Your question (optional)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _explain,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(isArabic ? 'شرح محلي' : 'Explain locally'),
            ),
            if (response != null) ...[
              const SizedBox(height: 16),
              Text(
                expertConfig(_expert).instructionAr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ...response.claims.map((claim) => _ClaimTile(claim: claim)),
              const SizedBox(height: 8),
              ...response.disclaimers(isArabic).map(
                (text) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $text', style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'نموذج مستضاف (مغلق افتراضيًا)' : 'Hosted model (off by default)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isArabic
                        ? 'الموافقة وحدها لا تُفعّل الإرسال؛ يجب أولاً استكمال مراجعة الخصوصية والتكلفة والترخيص.'
                        : 'Consent alone does not enable transfer; the privacy, cost and license review must be completed first.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _reviewHosted,
                          icon: const Icon(Icons.privacy_tip_outlined),
                          label: Text(isArabic ? 'مراجعة الإرسال' : 'Review transfer'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _clearSession,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(isArabic ? 'إزالة الجلسة' : 'Clear session'),
                        ),
                      ],
                    ),
                    if (_status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _status!,
                          style: TextStyle(color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({required this.claim});

  final GroundedClaim claim;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Chip(label: Text(claim.kind.label(isArabic))),
            const SizedBox(height: 6),
            Text(claim.text(isArabic)),
            for (final citation in claim.citations)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  '${citation.label}: ${citation.uri}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
