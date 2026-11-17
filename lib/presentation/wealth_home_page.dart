import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/wealth_dao.dart';
import '../data/wealth_database.dart';
import '../data/wealth_models.dart';
import '../data/wealth_mutations.dart';
import '../data/weekly_bundle_importer.dart';
import 'entity_editor_sheet.dart';
import 'imf_indicators_page.dart';
import 'wealth_profile_page.dart';

class WealthHomePage extends StatefulWidget {
  const WealthHomePage({
    required this.onLocaleChanged,
    this.database,
    super.key,
  });

  final ValueChanged<Locale> onLocaleChanged;
  final WealthDatabase? database;

  @override
  State<WealthHomePage> createState() => _WealthHomePageState();
}

class _WealthHomePageState extends State<WealthHomePage> {
  late final WealthDatabase _database;
  late final WealthDao _dao;
  late final WealthMutations _mutations;
  late final WeeklyBundleImporter _importer;
  final _queryController = TextEditingController();
  List<_WealthCardData> _cards = [];
  EntityCategory? _category;
  bool _hasEntities = false;
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? WealthDatabase();
    _dao = WealthDao(_database);
    _mutations = WealthMutations(_database);
    _importer = WeeklyBundleImporter(_database);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    if (widget.database == null) _database.close();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allEntities = await _dao.searchEntities('');
      final query = _queryController.text.trim();
      final entities = query.isEmpty && _category == null
          ? allEntities
          : await _dao.searchEntities(query, category: _category);
      final cards = entities.isEmpty
          ? <_WealthCardData>[]
          : await Future.wait(entities.map(_loadCard));
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _cards = cards;
        _hasEntities = allEntities.isNotEmpty;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<_WealthCardData> _loadCard(WealthEntity entity) async {
    final snapshots = await _dao.snapshotsFor(entity.id);
    final streams = await _dao.incomeStreamsFor(entity.id);
    WeeklySnapshot? latestValued;
    for (final snapshot in snapshots.reversed) {
      if (snapshot.totalNetWorth != null) {
        latestValued = snapshot;
        break;
      }
    }
    return _WealthCardData(
      entity: entity,
      snapshot: latestValued ?? (snapshots.isEmpty ? null : snapshots.last),
      streams: streams,
    );
  }

  Future<void> _createEntity() async {
    try {
      final linkTargets = await _linkTargets();
      if (!mounted) return;
      final draft = await showEntityEditor(
        context,
        isArabic: _isArabic,
        linkTargets: linkTargets,
      );
      if (draft == null || !mounted) return;
      final entity = await _mutations.createEntity(draft);
      await _reload();
      if (mounted) await _openProfile(entity);
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<List<WealthEntity>> _linkTargets() async {
    final entities = await _dao.searchEntities('');
    return entities
        .where(
          (entity) =>
              entity.category == EntityCategory.propertyAsset ||
              entity.category == EntityCategory.company,
        )
        .toList();
  }

  Future<void> _importBundle({String? jsonText, bool isSample = false}) async {
    final text = jsonText ?? await _askForBundle();
    if (text == null || text.trim().isEmpty) return;
    try {
      final summary = await _importer.importBundle(text);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSample
                ? (_isArabic
                      ? 'تم استيراد ${summary.entityCount} كيان من الحزمة التجريبية.'
                      : 'Imported ${summary.entityCount} entities from the sample pack.')
                : (_isArabic
                      ? 'تم استيراد ${summary.entityCount} كيان بنجاح.'
                      : 'Imported ${summary.entityCount} entities successfully.'),
          ),
        ),
      );
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _importSamplePack() async {
    try {
      final sample = await rootBundle.loadString(
        'assets/sample_weekly_pack.json',
      );
      await _importBundle(jsonText: sample, isSample: true);
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<String?> _askForBundle() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isArabic ? 'استيراد بيانات JSON' : 'Import Weekly JSON'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isArabic
                    ? 'الصق حزمة JSON بالإصدار 2.0. سيتم التحقق منها قبل حفظها محليًا.'
                    : 'Paste a version 2.0 JSON bundle. It will be validated before being saved on this device.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 10,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: '{"bundleVersion":"2.0", ...}',
                  border: const OutlineInputBorder(),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () async {
                    final sample = await rootBundle.loadString(
                      'assets/seed/weekly_bundle_v2.json',
                    );
                    controller.text = sample;
                  },
                  icon: const Icon(Icons.science_outlined),
                  label: Text(
                    _isArabic
                        ? 'استخدام عينة خيالية'
                        : 'Use fictional sample bundle',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(_isArabic ? 'استيراد' : 'Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _openProfile(WealthEntity entity) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            WealthProfilePage(entityId: entity.id, database: _database),
      ),
    );
    if (mounted) _reload();
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
        title: Text(isArabic ? 'الثروة' : 'Wealth'),
        actions: [
          IconButton(
            tooltip: isArabic ? 'مؤشرات صندوق النقد' : 'IMF indicators',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    ImfIndicatorsPage(onLocaleChanged: widget.onLocaleChanged),
              ),
            ),
            icon: const Icon(Icons.public_outlined),
          ),
          if (_hasEntities)
            PopupMenuButton<String>(
              tooltip: isArabic ? 'المزيد' : 'More',
              onSelected: (value) {
                switch (value) {
                  case 'import':
                    _importBundle();
                  case 'sample':
                    _importSamplePack();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'import',
                  child: Text(
                    isArabic ? 'استيراد JSON أسبوعي' : 'Import Weekly JSON',
                  ),
                ),
                PopupMenuItem(
                  value: 'sample',
                  child: Text(
                    isArabic
                        ? 'استيراد حزمة بيانات تجريبية'
                        : 'Import Sample Pack',
                  ),
                ),
              ],
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _queryController,
              onChanged: (_) => _reload(),
              decoration: InputDecoration(
                hintText: isArabic ? 'ابحث في معرفتك' : 'Search your knowledge',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _queryController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: isArabic ? 'مسح البحث' : 'Clear search',
                        onPressed: () {
                          _queryController.clear();
                          _reload();
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          _CategoryFilters(
            isArabic: isArabic,
            selected: _category,
            onChanged: (value) {
              setState(() => _category = value);
              _reload();
            },
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!)))
          else if (_cards.isEmpty)
            Expanded(
              child: _hasEntities
                  ? _NoWealthResults(
                      isArabic: isArabic,
                      onClear: () {
                        _queryController.clear();
                        setState(() => _category = null);
                        _reload();
                      },
                    )
                  : _EmptyWealthState(
                      isArabic: isArabic,
                      onCreate: _createEntity,
                      onImportSample: _importSamplePack,
                    ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                itemCount: _cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final card = _cards[index];
                  return _WealthEntityCard(
                    data: card,
                    isArabic: isArabic,
                    onTap: () => _openProfile(card.entity),
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: !_loading && _error == null && _hasEntities
          ? FloatingActionButton.extended(
              onPressed: _createEntity,
              icon: const Icon(Icons.add),
              label: Text(isArabic ? 'إضافة كيان' : 'Add entity'),
            )
          : null,
    );
  }
}

class _WealthCardData {
  const _WealthCardData({
    required this.entity,
    required this.snapshot,
    required this.streams,
  });

  final WealthEntity entity;
  final WeeklySnapshot? snapshot;
  final List<IncomeStream> streams;
}

class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters({
    required this.isArabic,
    required this.selected,
    required this.onChanged,
  });

  final bool isArabic;
  final EntityCategory? selected;
  final ValueChanged<EntityCategory?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 50,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: [
        _chip(context, null, isArabic ? 'الكل' : 'All'),
        for (final category in EntityCategory.values)
          _chip(context, category, _categoryLabel(category, isArabic)),
      ],
    ),
  );

  Widget _chip(BuildContext context, EntityCategory? category, String label) =>
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: FilterChip(
          key: ValueKey<String>(
            'wealth-category-filter-${category?.value ?? 'ALL'}',
          ),
          label: Text(label),
          selected: selected == category,
          onSelected: (_) => onChanged(category),
        ),
      );
}

class _WealthEntityCard extends StatelessWidget {
  const _WealthEntityCard({
    required this.data,
    required this.isArabic,
    required this.onTap,
  });

  final _WealthCardData data;
  final bool isArabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final snapshot = data.snapshot;
    final streams =
        data.streams
            .where((stream) => stream.portfolioSharePercent != null)
            .toList()
          ..sort(
            (a, b) =>
                b.portfolioSharePercent!.compareTo(a.portfolioSharePercent!),
          );
    final topStreams = streams.take(2).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    child: Icon(_categoryIcon(data.entity.category)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.entity.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (data.entity.subtitle?.isNotEmpty ?? false)
                          Text(data.entity.subtitle!),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _CategoryBadge(
                    label: _categoryLabel(data.entity.category, isArabic),
                  ),
                  if (snapshot?.totalNetWorth != null)
                    Text(
                      _formatWorth(
                        snapshot!.totalNetWorth!,
                        snapshot.currencyUnit,
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    )
                  else
                    Text(isArabic ? 'لا يوجد تقدير بعد' : 'No estimate yet'),
                  if (snapshot?.wowChangePercent != null)
                    _ChangeBadge(change: snapshot!.wowChangePercent!),
                ],
              ),
              if (topStreams.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final stream in topStreams)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${stream.portfolioSharePercent!.toStringAsFixed(0)}% '
                          '${_streamLabel(stream.streamType, isArabic)}',
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    ),
  );
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change});

  final double change;

  @override
  Widget build(BuildContext context) {
    final positive = change >= 0;
    final color = positive ? Colors.green.shade300 : Colors.red.shade300;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '${positive ? '+' : ''}${change.toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _EmptyWealthState extends StatelessWidget {
  const _EmptyWealthState({
    required this.isArabic,
    required this.onCreate,
    required this.onImportSample,
  });

  final bool isArabic;
  final VoidCallback onCreate;
  final VoidCallback onImportSample;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - 64).clamp(0, double.infinity),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hub_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                isArabic ? 'ابدأ مساحة معرفتك بإضافة أول كيان ومصدره.' : 'Start your knowledge space by adding an entity and its source.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                isArabic
                    ? 'ستبقى بياناتك محفوظة على هذا الجهاز فقط.'
                    : 'Everything you add stays on this device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: Text(isArabic ? 'إضافة كيان' : 'Add entity'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onImportSample,
                icon: const Icon(Icons.download_outlined),
                label: Text(
                  isArabic
                      ? 'استيراد حزمة بيانات تجريبية'
                      : 'Import Sample Pack',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NoWealthResults extends StatelessWidget {
  const _NoWealthResults({required this.isArabic, required this.onClear});

  final bool isArabic;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isArabic ? 'لا توجد نتائج' : 'No results found'),
        TextButton(
          onPressed: onClear,
          child: Text(isArabic ? 'مسح عوامل التصفية' : 'Clear filters'),
        ),
      ],
    ),
  );
}

String _categoryLabel(EntityCategory category, bool isArabic) =>
    switch (category) {
      EntityCategory.athlete => isArabic ? 'اللاعبون' : 'Athletes',
      EntityCategory.artist => isArabic ? 'الفنانون' : 'Artists',
      EntityCategory.businessFigure =>
        isArabic ? 'شخصيات الأعمال' : 'Business figures',
      EntityCategory.company => isArabic ? 'الشركات' : 'Companies',
      EntityCategory.propertyAsset => isArabic ? 'الممتلكات' : 'Properties',
      EntityCategory.economicNews =>
        isArabic ? 'الأخبار الاقتصادية' : 'Economic news',
    };

IconData _categoryIcon(EntityCategory category) => switch (category) {
  EntityCategory.athlete => Icons.sports,
  EntityCategory.artist => Icons.mic,
  EntityCategory.businessFigure => Icons.person,
  EntityCategory.company => Icons.business,
  EntityCategory.propertyAsset => Icons.real_estate_agent,
  EntityCategory.economicNews => Icons.newspaper,
};

String _streamLabel(IncomeStreamType type, bool isArabic) => switch (type) {
  IncomeStreamType.salaryContract => isArabic ? 'عقود' : 'Contracts',
  IncomeStreamType.endorsementsAds => isArabic ? 'إعلانات' : 'Ads',
  IncomeStreamType.royaltiesStreaming => isArabic ? 'حقوق' : 'Royalties',
  IncomeStreamType.toursEvents => isArabic ? 'فعاليات' : 'Events',
  IncomeStreamType.businessEquity => isArabic ? 'أعمال' : 'Business',
  IncomeStreamType.realEstate => isArabic ? 'عقارات' : 'Real estate',
  IncomeStreamType.investmentsStocks => isArabic ? 'استثمارات' : 'Investments',
};

String formatNetWorth(double value, String currencyUnit) {
  final amount = currencyUnit == 'USD_B' ? value * 1000 : value;
  if (amount.abs() >= 1000) {
    return '\$${_trimNumber(amount / 1000)}B';
  }
  return '\$${_trimNumber(amount)}M';
}

String _formatWorth(double value, String currencyUnit) =>
    formatNetWorth(value, currencyUnit);

String _trimNumber(double value) =>
    value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
