import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/ai_consent.dart';
import '../data/ai_experts.dart';
import '../data/ai_grounding.dart';
import '../data/ai_models.dart';
import '../data/hosted_ai.dart';
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
  final _settingsStore = const HostedAiSettingsStore();
  late final AiConsentManager _consent;

  AiExpertKind _expert = AiExpertKind.equationTutor;
  String _equationId = equationCatalog.first.id;
  GroundedResponse? _response;
  String? _status;
  HostedAiSettings _settings = const HostedAiSettings();
  String? _hostedText;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _consent = AiConsentManager(
      transport: HttpHostedAiTransport(settingsProvider: _settingsStore.load),
    );
    _loadHostedSettings();
  }

  Future<void> _loadHostedSettings() async {
    try {
      final settings = await _settingsStore.load();
      if (!mounted) return;
      setState(() => _settings = settings);
      _consent.setHostedEnabled(settings.isConfigured);
    } on Object {
      // Keep the hosted API disabled if settings cannot be read.
    }
  }

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
      final text = await _consent.sendToHosted(payload);
      if (!mounted) return;
      setState(() {
        _hostedText = text;
        _status = _isArabic
            ? 'تم استلام الرد؛ رُفض أي رقم غير موجود في الحمولة.'
            : 'Response received; any number absent from the payload was rejected.';
      });
    } on AiHostedDisabled {
      if (!mounted) return;
      setState(() {
        _hostedText = null;
        _status = _isArabic
            ? 'النقل إلى نموذج مستضاف غير مُفعّل؛ اضبط إعدادات النموذج أولاً.'
            : 'Hosted transfer is disabled; configure the provider first.';
      });
    } on AiConsentRequired {
      if (!mounted) return;
      setState(() => _status = _isArabic
          ? 'الموافقة مطلوبة قبل أي إرسال.'
          : 'Consent is required before any transfer.');
    } on AiHostedOutputRejected catch (error) {
      if (!mounted) return;
      setState(() {
        _hostedText = null;
        _status = '${_isArabic ? 'رُفض الرد' : 'Response rejected'}: ${error.reason}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _hostedText = null;
        _status = error.toString();
      });
    }
  }

  Future<void> _editHostedSettings() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _HostedSettingsDialog(
        isArabic: _isArabic,
        settings: _settings,
        onSave: _settingsStore.save,
        onClear: _settingsStore.clear,
      ),
    );
    if (changed != true || !mounted) return;
    await _loadHostedSettings();
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
                      isArabic
                          ? (_settings.isConfigured
                              ? 'نموذج مستضاف • ${_settings.model}'
                              : 'نموذج مستضاف (مغلق افتراضيًا)')
                          : (_settings.isConfigured
                              ? 'Hosted model • ${_settings.model}'
                              : 'Hosted model (off by default)'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isArabic
                          ? 'المفتاح يُدخل وقت التشغيل ويُحفظ على الجهاز فقط؛ كل إرسال يتطلب مراجعة الحمولة والموافقة.'
                          : 'The key is entered at runtime and stored on-device only; every request requires a payload review and consent.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _editHostedSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(isArabic ? 'إعدادات النموذج' : 'Model settings'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _reviewHosted,
                          icon: const Icon(Icons.privacy_tip_outlined),
                          label: Text(
                            isArabic
                                ? (_settings.isConfigured
                                    ? 'إرسال للنموذج'
                                    : 'مراجعة الإرسال')
                                : (_settings.isConfigured
                                    ? 'Send to model'
                                    : 'Review transfer'),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _clearSession,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(isArabic ? 'إزالة الجلسة' : 'Clear session'),
                        ),
                      ],
                    ),
                    if (_hostedText != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          _hostedText!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          isArabic
                              ? 'نص مُولّد للصياغة فقط؛ الأرقام النهائية من المحرك الحتمي.'
                              : 'Generated wording only; final numbers come from the deterministic engine.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
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

class _HostedSettingsDialog extends StatefulWidget {
  const _HostedSettingsDialog({
    required this.isArabic,
    required this.settings,
    required this.onSave,
    required this.onClear,
  });

  final bool isArabic;
  final HostedAiSettings settings;
  final Future<void> Function(HostedAiSettings settings) onSave;
  final Future<void> Function() onClear;

  @override
  State<_HostedSettingsDialog> createState() => _HostedSettingsDialogState();
}

class _HostedSettingsDialogState extends State<_HostedSettingsDialog> {
  late final TextEditingController _baseUrl = TextEditingController(
    text: widget.settings.baseUrl,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.settings.model,
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.settings.apiKey,
  );
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        HostedAiSettings(
          apiKey: _key.text.trim(),
          baseUrl: _baseUrl.text.trim(),
          model: _model.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _clear() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onClear();
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.isArabic;
    return AlertDialog(
      title: Text(ar ? 'إعدادات النموذج المُستضاف' : 'Hosted model settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ar
                  ? 'تُحفظ هذه القيم على الجهاز فقط. يُرسل المفتاح في ترويسةAuthorization إلى المزوّد الذي تختاره فقط، ولا يُضاف إلى السجلات أو الروابط.'
                  : 'Stored on this device only. The key is sent in an Authorization header to your chosen provider only, never in logs or URLs.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrl,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: ar ? 'Base URL' : 'Base URL',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _model,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: ar ? 'اسم النموذج' : 'Model name',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: ar ? 'مفتاح API' : 'API key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? (ar ? 'إظهار' : 'Show') : (ar ? 'إخفاء' : 'Hide'),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.settings.isConfigured)
          TextButton(
            onPressed: _saving ? null : _clear,
            child: Text(ar ? 'حذف' : 'Clear'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(ar ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(ar ? 'حفظ' : 'Save'),
        ),
      ],
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
