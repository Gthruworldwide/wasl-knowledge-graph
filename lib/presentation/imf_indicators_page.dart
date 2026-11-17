import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/fmp_context.dart';
import '../data/imf_cpi_catalog.dart';
import '../data/imf_observation.dart';
import '../data/imf_repository.dart';
import '../data/imf_sdmx_client.dart';
import '../data/wealth_database.dart';
import 'wealth_profile_page.dart';

class ImfIndicatorsPage extends StatefulWidget {
  const ImfIndicatorsPage({
    required this.onLocaleChanged,
    this.database,
    this.repository,
    super.key,
  });

  final ValueChanged<Locale> onLocaleChanged;
  final WealthDatabase? database;
  final ImfRepository? repository;

  @override
  State<ImfIndicatorsPage> createState() => _ImfIndicatorsPageState();
}

class _ImfIndicatorsPageState extends State<ImfIndicatorsPage> {
  late final WealthDatabase _database;
  late final ImfRepository _repository;
  final List<_ImfCardData> _cards = [];
  ImfSettings _settings = const ImfSettings(
    countryCodes: defaultImfCountryCodes,
    autoRefresh: false,
    startYear: 2022,
    apiVersion: ImfApiVersion.v21,
  );
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  bool _fmpSyncing = false;
  bool _hasFmpKey = false;
  List<FmpContextRow> _fmpCpi = const <FmpContextRow>[];
  List<FmpContextRow> _fmpQuotes = const <FmpContextRow>[];

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? WealthDatabase();
    _repository = widget.repository ?? ImfRepository(_database);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      await _maybeAutoRefresh();
    });
  }

  @override
  void dispose() {
    if (widget.database == null && widget.repository == null) {
      _database.close();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _repository.loadSettings();
      final latest = await _repository.latestObservations();
      final cards = await Future.wait(latest.map(_loadCard));
      final fmpCpi = await _repository.fmpContext(kind: FmpContextKind.cpi);
      final fmpQuotes =
          await _repository.fmpContext(kind: FmpContextKind.indexQuote);
      final hasFmpKey = await _repository.hasFmpApiKey();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _cards
          ..clear()
          ..addAll(cards);
        _fmpCpi = fmpCpi;
        _fmpQuotes = fmpQuotes;
        _hasFmpKey = hasFmpKey;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<_ImfCardData> _loadCard(ImfObservationRow observation) async {
    final history = await _repository.historyFor(
      observation.countryCode,
      limit: 13,
    );
    final previous = history.length > 1 ? history[history.length - 2] : null;
    final change = previous == null || previous.value == 0
        ? null
        : ((observation.value - previous.value) / previous.value.abs()) * 100;
    return _ImfCardData(
      observation: observation,
      changePercent: change,
      history: history.map((item) => item.value).toList(),
    );
  }

  Future<void> _maybeAutoRefresh() async {
    try {
      if (!await _repository.shouldAutoRefresh()) return;
      await _sync(silent: true);
    } on Object {
      // Offline or stale data is fine: cached observations stay available.
    }
  }

  Future<void> _sync({bool silent = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final summary = await _repository.importCpi(
        countryCodes: _settings.countryCodes,
        startYear: _settings.startYear,
        isArabic: _isArabic,
      );
      await _reload();
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isArabic
                ? 'تم تحديث ${summary.countryCount} دولة و${summary.observationCount} مشاهدة من صندوق النقد.'
                : 'Updated ${summary.countryCount} countries and '
                    '${summary.observationCount} observations from the IMF.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _changeCountries() async {
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _CountryPickerDialog(
        isArabic: _isArabic,
        selected: _settings.countryCodes,
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    try {
      final updated = _settings.copyWith(countryCodes: selected);
      await _repository.saveSettings(updated);
      await _reload();
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _setAutoRefresh(bool enabled) async {
    try {
      final updated = _settings.copyWith(autoRefresh: enabled);
      await _repository.saveSettings(updated);
      setState(() => _settings = updated);
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _setApiVersion(ImfApiVersion version) async {
    try {
      final updated = _settings.copyWith(apiVersion: version);
      await _repository.saveSettings(updated);
      setState(() => _settings = updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isArabic
                ? 'تم حفظ إصدار SDMX ${version.label}. اضغط تحديث الآن لتجربته.'
                : 'SDMX ${version.label} saved. Tap “Sync now” to use it.',
          ),
        ),
      );
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _syncFmp() async {
    if (_fmpSyncing) return;
    setState(() => _fmpSyncing = true);
    try {
      final summary = await _repository.syncFmpContext(isArabic: _isArabic);
      await _reload();
      if (!mounted) return;
      final warnings = summary.errors.isEmpty
          ? ''
          : ' ${_isArabic ? 'تحذيرات' : 'Warnings'}: '
              '${summary.errors.join(' ')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isArabic
                ? 'تم تحديث ${summary.rowCount} عنصر من FMP.$warnings'
                : 'Updated ${summary.rowCount} FMP context items.$warnings',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _fmpSyncing = false);
    }
  }

  Future<void> _editFmpKey() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _FmpKeyDialog(
        isArabic: _isArabic,
        hasKey: _hasFmpKey,
        onSave: _repository.saveFmpApiKey,
        onClear: _repository.clearFmpApiKey,
      ),
    );
    if (changed != true || !mounted) return;
    await _reload();
  }

  Future<void> _openWealthNote(String countryCode) async {
    try {
      final entity = await _repository.newsEntityFor(countryCode);
      if (entity == null || !mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              WealthProfilePage(entityId: entity.id, database: _database),
        ),
      );
    } on Object catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? 'مؤشرات صندوق النقد' : 'IMF Indicators',
        ),
        actions: [
          IconButton(
            tooltip: isArabic ? 'تحديث الآن' : 'Sync now',
            onPressed: _syncing ? null : () => _sync(),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: isArabic ? 'English' : 'العربية',
            onPressed: () => widget.onLocaleChanged(
              isArabic ? const Locale('en') : const Locale('ar'),
            ),
            icon: const Icon(Icons.translate),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _SourceHeader(
              isArabic: isArabic,
              lastSyncAt: _settings.lastSyncAt,
              syncing: _syncing,
              onSync: () => _sync(),
              autoRefresh: _settings.autoRefresh,
              onAutoRefreshChanged: _setAutoRefresh,
              apiVersion: _settings.apiVersion,
              onApiVersionChanged: _setApiVersion,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _FmpContextCard(
              isArabic: isArabic,
              hasKey: _hasFmpKey,
              cpi: _fmpCpi,
              quotes: _fmpQuotes,
              syncing: _fmpSyncing,
              onSync: _syncFmp,
              onEditKey: _editFmpKey,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isArabic
                        ? '${_settings.countryCodes.length} دول • مؤشر أسعار المستهلكين السنوي'
                        : '${_settings.countryCodes.length} countries • annual CPI inflation',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _changeCountries,
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(isArabic ? 'الدول' : 'Countries'),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!)))
          else if (_cards.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.public_off, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        isArabic
                            ? 'لا توجد بيانات محلية بعد. اضغط "تحديث الآن" لجلب بيانات صندوق النقد.'
                            : 'No cached IMF data yet. Tap “Sync now” to fetch it.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: _cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final card = _cards[index];
                  return _ImfIndicatorCard(
                    data: card,
                    isArabic: isArabic,
                    onTap: () => _openWealthNote(
                      card.observation.countryCode,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ImfCardData {
  const _ImfCardData({
    required this.observation,
    required this.changePercent,
    required this.history,
  });

  final ImfObservationRow observation;
  final double? changePercent;
  final List<double> history;
}

class _SourceHeader extends StatelessWidget {
  const _SourceHeader({
    required this.isArabic,
    required this.lastSyncAt,
    required this.syncing,
    required this.onSync,
    required this.autoRefresh,
    required this.onAutoRefreshChanged,
    required this.apiVersion,
    required this.onApiVersionChanged,
  });

  final bool isArabic;
  final String? lastSyncAt;
  final bool syncing;
  final VoidCallback onSync;
  final bool autoRefresh;
  final ValueChanged<bool> onAutoRefreshChanged;
  final ImfApiVersion apiVersion;
  final ValueChanged<ImfApiVersion> onApiVersionChanged;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(lastSyncAt ?? '');
    final lastSync = parsed?.toLocal().toIso8601String().substring(0, 16);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isArabic
                        ? 'بيانات صندوق النقد الدولي • SDMX ${apiVersion.label}'
                        : 'International Monetary Fund • SDMX ${apiVersion.label}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'تُحفظ البيانات على جهازك، وتُنشأ ملاحظات اقتصادية مرتبطة بالكيانات.'
                  : 'Data is stored on this device and linked economic notes '
                      'are added to your graph.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  isArabic ? 'إصدار API:' : 'API version:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                DropdownButton<ImfApiVersion>(
                  value: apiVersion,
                  onChanged: (version) {
                    if (version != null) onApiVersionChanged(version);
                  },
                  items: [
                    for (final version in ImfApiVersion.values)
                      DropdownMenuItem<ImfApiVersion>(
                        value: version,
                        child: Text('SDMX ${version.label}'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    lastSync == null
                        ? (isArabic ? 'لم يتم التحديث بعد' : 'Never synced')
                        : '${isArabic ? 'آخر تحديث' : 'Last sync'}: $lastSync',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: syncing ? null : onSync,
                  icon: syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    isArabic ? 'تحديث الآن' : 'Sync now',
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: autoRefresh,
              onChanged: onAutoRefreshChanged,
              title: Text(
                isArabic ? 'تحديث تلقائي عند الفتح' : 'Auto-refresh on open',
              ),
              subtitle: Text(
                isArabic
                    ? 'مرة كل 24 ساعة عند فتح هذه الشاشة'
                    : 'Once every 24 hours when this screen opens',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FmpContextCard extends StatelessWidget {
  const _FmpContextCard({
    required this.isArabic,
    required this.hasKey,
    required this.cpi,
    required this.quotes,
    required this.syncing,
    required this.onSync,
    required this.onEditKey,
  });

  final bool isArabic;
  final bool hasKey;
  final List<FmpContextRow> cpi;
  final List<FmpContextRow> quotes;
  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback onEditKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latestCpi = cpi.isEmpty ? null : cpi.first;
    final all = <FmpContextRow>[...cpi, ...quotes];
    final lastFetched = all.isEmpty
        ? null
        : all
            .map((row) => row.fetchedAt)
            .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isArabic
                        ? 'سياق الأسواق • Financial Modeling Prep'
                        : 'Market context • Financial Modeling Prep',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? (hasKey
                      ? 'المفتاح محفوظ على هذا الجهاز فقط.'
                      : 'لم يتم إدخال مفتاح API بعد.')
                  : (hasKey
                      ? 'API key saved on this device only.'
                      : 'No API key entered yet.'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    lastFetched == null
                        ? (isArabic ? 'لا توجد بيانات محفوظة' : 'Nothing cached yet')
                        : '${isArabic ? 'آخر جلب' : 'Last fetch'}: '
                            '${_shortTime(lastFetched)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: onEditKey,
                  icon: const Icon(Icons.key_outlined),
                  label: Text(isArabic ? 'المفتاح' : 'API key'),
                ),
                FilledButton.icon(
                  onPressed: hasKey && !syncing ? onSync : null,
                  icon: syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                  label: Text(isArabic ? 'جلب FMP' : 'Sync FMP'),
                ),
              ],
            ),
            if (latestCpi != null) ...[
              const SizedBox(height: 8),
              Text(
                '${isArabic ? 'مؤشر أسعار المستهلكين (FMP)' : 'CPI (FMP)'}: '
                '${latestCpi.value.toStringAsFixed(2)} • ${latestCpi.period}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (quotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final quote in quotes)
                    _FmpQuoteChip(quote: quote, isArabic: isArabic),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'يُرسل المفتاح في ترويسة الطلب فقط، ولا يُحفظ في روابط المصادر.'
                  : 'The key is sent only in a request header and is never '
                      'saved in provenance URLs.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _shortTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return parsed.toLocal().toIso8601String().substring(0, 16);
  }
}

class _FmpQuoteChip extends StatelessWidget {
  const _FmpQuoteChip({required this.quote, required this.isArabic});

  final FmpContextRow quote;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final change = quote.changePercent;
    final changeText = change == null
        ? '—'
        : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
    final changeColor = change == null
        ? null
        : (change >= 0 ? Colors.green.shade300 : Colors.red.shade300);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quote.label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                quote.value.toStringAsFixed(2),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 6),
              Text(
                changeText,
                style: TextStyle(
                  color: changeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FmpKeyDialog extends StatefulWidget {
  const _FmpKeyDialog({
    required this.isArabic,
    required this.hasKey,
    required this.onSave,
    required this.onClear,
  });

  final bool isArabic;
  final bool hasKey;
  final Future<void> Function(String apiKey) onSave;
  final Future<void> Function() onClear;

  @override
  State<_FmpKeyDialog> createState() => _FmpKeyDialogState();
}

class _FmpKeyDialogState extends State<_FmpKeyDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(
        () => _error = widget.isArabic
            ? 'أدخل مفتاحاً صالحاً.'
            : 'Enter a key first.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(key);
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
    return AlertDialog(
      title: Text(widget.isArabic ? 'مفتاح FMP' : 'FMP API key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isArabic
                ? 'أدخل المفتاح الذي حصلت عليه من Financial Modeling Prep. '
                    'يُحفظ على هذا الجهاز فقط ولا يُضاف إلى الكود أو المستندات.'
                : 'Enter the key from your Financial Modeling Prep dashboard. '
                    'It is stored on this device only and never added to '
                    'source or documentation.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: widget.isArabic ? 'API Key' : 'API key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure
                    ? (widget.isArabic ? 'إظهار' : 'Show')
                    : (widget.isArabic ? 'إخفاء' : 'Hide'),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (widget.hasKey)
          TextButton(
            onPressed: _saving ? null : _clear,
            child: Text(widget.isArabic ? 'حذف' : 'Clear'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(widget.isArabic ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(widget.isArabic ? 'حفظ' : 'Save'),
        ),
      ],
    );
  }
}

class _ImfIndicatorCard extends StatelessWidget {
  const _ImfIndicatorCard({
    required this.data,
    required this.isArabic,
    required this.onTap,
  });

  final _ImfCardData data;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final observation = data.observation;
    final country = imfCountry(observation.countryCode);
    final name = country?.label(isArabic) ?? observation.countryName;
    final change = data.changePercent;
    final changeText = change == null
        ? '—'
        : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
    final valueText = '${observation.value.toStringAsFixed(2)}%';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      isArabic
                          ? 'تضخم سنوي • كل السلع • ${observation.period}'
                          : 'YoY inflation • All items • ${observation.period}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          valueText,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(width: 8),
                        if (change != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: change >= 0
                                  ? Colors.red.withValues(alpha: 0.16)
                                  : Colors.green.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              changeText,
                              style: TextStyle(
                                color: change >= 0
                                    ? Colors.red.shade300
                                    : Colors.green.shade300,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 96,
                height: 56,
                child: _ImfSparkline(values: data.history),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImfSparkline extends StatelessWidget {
  const _ImfSparkline({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ImfSparklinePainter(values),
      size: Size.infinite,
    );
  }
}

class _ImfSparklinePainter extends CustomPainter {
  const _ImfSparklinePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var min = values.first;
    var max = values.first;
    for (final value in values) {
      min = math.min(min, value);
      max = math.max(max, value);
    }
    final span = max - min;
    final paint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = index / (values.length - 1) * size.width;
      final ratio = span == 0 ? 0.5 : (values[index] - min) / span;
      final y = size.height - (ratio * (size.height - 8) + 4);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ImfSparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}

class _CountryPickerDialog extends StatefulWidget {
  const _CountryPickerDialog({required this.isArabic, required this.selected});

  final bool isArabic;
  final List<String> selected;

  @override
  State<_CountryPickerDialog> createState() => _CountryPickerDialogState();
}

class _CountryPickerDialogState extends State<_CountryPickerDialog> {
  late final Set<String> _selected = widget.selected.toSet();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isArabic ? 'اختر الدول' : 'Select countries'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: ListView(
          children: [
            for (final country in imfCpiCountries)
              CheckboxListTile(
                value: _selected.contains(country.code),
                onChanged: (checked) {
                  setState(() {
                    if (checked ?? false) {
                      _selected.add(country.code);
                    } else {
                      _selected.remove(country.code);
                    }
                  });
                },
                title: Text(country.label(widget.isArabic)),
                subtitle: Text(country.code),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.isArabic ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: Text(widget.isArabic ? 'حفظ' : 'Save'),
        ),
      ],
    );
  }
}
