import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/wealth_dao.dart';
import '../data/wealth_database.dart';
import '../data/wealth_models.dart';

class WealthProfilePage extends StatefulWidget {
  const WealthProfilePage({
    required this.entityId,
    required this.database,
    super.key,
  });

  final String entityId;
  final WealthDatabase database;

  @override
  State<WealthProfilePage> createState() => _WealthProfilePageState();
}

class _WealthProfilePageState extends State<WealthProfilePage> {
  late final WealthDao _dao = WealthDao(widget.database);
  _WealthProfileData? _data;
  String? _error;
  bool _loading = true;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final entity = await _dao.getEntity(widget.entityId);
      if (entity == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = null;
        });
        return;
      }
      final snapshots = await _dao.snapshotsFor(entity.id);
      final streams = await _dao.incomeStreamsFor(entity.id);
      final relations = await _dao.relationsFor(entity.id);
      final relatedIds = relations
          .map(
            (relation) => relation.fromEntityId == entity.id
                ? relation.toEntityId
                : relation.fromEntityId,
          )
          .toSet();
      final relatedResults = await Future.wait(
        relatedIds.map((id) async => MapEntry(id, await _dao.getEntity(id))),
      );
      final sourceIds = <String>{
        if (entity.sourceId != null) entity.sourceId!,
        for (final snapshot in snapshots) snapshot.sourceId,
        for (final relation in relations)
          if (relation.sourceId != null) relation.sourceId!,
      };
      final sourceResults = await Future.wait(
        sourceIds.map((id) async => MapEntry(id, await _dao.getSource(id))),
      );
      final data = _WealthProfileData(
        entity: entity,
        snapshots: snapshots,
        streams: streams,
        relations: relations,
        relatedEntities: {
          for (final result in relatedResults)
            if (result.value != null) result.key: result.value!,
        },
        sources: {
          for (final result in sourceResults)
            if (result.value != null) result.key: result.value!,
        },
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = _isArabic;
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          data?.entity.name ?? (isArabic ? 'الملف الشخصي' : 'Profile'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : data == null
          ? Center(
              child: Text(
                isArabic ? 'لم يتم العثور على الكيان.' : 'Entity not found.',
              ),
            )
          : _buildProfile(data, isArabic),
    );
  }

  Widget _buildProfile(_WealthProfileData data, bool isArabic) {
    final latest = data.snapshots.isEmpty ? null : data.snapshots.last;
    final currentSource = data.entity.sourceId == null
        ? null
        : data.sources[data.entity.sourceId];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(isArabic ? 'ملخص الثروة' : 'Wealth summary'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CategoryBadge(
                  label: _categoryLabel(data.entity.category, isArabic),
                ),
                if (data.entity.subtitle?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(data.entity.subtitle!),
                ],
                const SizedBox(height: 16),
                if (latest?.totalNetWorth != null)
                  Text(
                    _formatNetWorth(
                      latest!.totalNetWorth!,
                      latest.currencyUnit,
                    ),
                    style: Theme.of(context).textTheme.headlineMedium,
                  )
                else
                  Text(
                    isArabic
                        ? 'لا يوجد تقدير لصافي الثروة بعد'
                        : 'No net worth estimate yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                if (latest != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      latest.weekIdentifier,
                      if (latest.wowChangePercent != null)
                        '${isArabic ? 'التغير الأسبوعي' : 'WoW'} '
                            '${latest.wowChangePercent! >= 0 ? '+' : ''}'
                            '${latest.wowChangePercent!.toStringAsFixed(1)}%',
                    ].join(' · '),
                  ),
                ],
                const SizedBox(height: 16),
                if (data.snapshots.length > 1)
                  SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _NetWorthChartPainter(
                        values: data.snapshots.map(_normalizedWorth).toList(),
                        lineColor: Theme.of(context).colorScheme.primary,
                        gridColor: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      child: Semantics(
                        label: isArabic
                            ? 'رسم يوضح تغير صافي الثروة عبر الأسابيع'
                            : 'Chart of net worth over recorded weeks',
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      isArabic
                          ? 'أضف لقطات أسبوعية متعددة لعرض الاتجاه التاريخي.'
                          : 'Add multiple weekly snapshots to see the historical trend.',
                    ),
                  ),
                if (currentSource != null)
                  _SourceCitation(source: currentSource, isArabic: isArabic),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle(
          isArabic ? 'التنوع ومصادر الدخل' : 'Income diversification',
        ),
        if (data.streams.isEmpty)
          _NoRecords(
            isArabic
                ? 'لا توجد مصادر دخل مسجلة بعد.'
                : 'No income streams recorded yet.',
          )
        else ...[
          _DiversificationBar(streams: data.streams),
          const SizedBox(height: 8),
          for (final stream in data.streams)
            Card(
              child: ListTile(
                leading: const Icon(Icons.pie_chart_outline),
                title: Text(stream.title),
                subtitle: Text(
                  [
                    _streamLabel(stream.streamType, isArabic),
                    if (stream.lastUpdatedWeek.isNotEmpty)
                      stream.lastUpdatedWeek,
                  ].join(' · '),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (stream.portfolioSharePercent != null)
                      Text(
                        '${stream.portfolioSharePercent!.toStringAsFixed(0)}%',
                      ),
                    if (stream.estimatedAnnualValue != null)
                      Text(
                        '${_formatNetWorth(stream.estimatedAnnualValue!, 'USD_M')}/${isArabic ? 'سنة' : 'yr'}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 20),
        _SectionTitle(isArabic ? 'الممتلكات والحصص' : 'Properties & holdings'),
        ..._buildRelations(data, const {
          EntityRelationType.ownsProperty,
          EntityRelationType.ownsStake,
        }, isArabic),
        const SizedBox(height: 20),
        _SectionTitle(
          isArabic ? 'التحديثات الأسبوعية والأخبار' : 'Weekly updates & news',
        ),
        if (data.snapshots.every(
          (snapshot) => (snapshot.summaryNote?.isNotEmpty ?? false) == false,
        ))
          _NoRecords(
            isArabic
                ? 'لا توجد تحديثات أسبوعية بعد.'
                : 'No weekly updates recorded yet.',
          )
        else
          for (final snapshot in data.snapshots.reversed)
            if (snapshot.summaryNote?.isNotEmpty ?? false)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        snapshot.weekIdentifier,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(snapshot.summaryNote!),
                      if (data.sources[snapshot.sourceId] case final source?)
                        _SourceCitation(source: source, isArabic: isArabic),
                    ],
                  ),
                ),
              ),
        ..._buildRelations(
          data,
          const {
            EntityRelationType.impactedByNews,
            EntityRelationType.sponsoredBy,
            EntityRelationType.playsFor,
          },
          isArabic,
          sectionTitle: null,
        ),
      ],
    );
  }

  List<Widget> _buildRelations(
    _WealthProfileData data,
    Set<EntityRelationType> types,
    bool isArabic, {
    String? sectionTitle,
  }) {
    final relations = data.relations
        .where((relation) => types.contains(relation.relationType))
        .toList();
    return [
      if (sectionTitle != null) _SectionTitle(sectionTitle),
      if (relations.isEmpty)
        _NoRecords(
          isArabic
              ? 'لا توجد روابط مسجلة بعد.'
              : 'No connections recorded yet.',
        )
      else
        for (final relation in relations)
          if (data.relatedEntities[relation.fromEntityId == data.entity.id
                  ? relation.toEntityId
                  : relation.fromEntityId]
              case final related?)
            Card(
              child: ListTile(
                leading: Icon(
                  relation.relationType == EntityRelationType.impactedByNews
                      ? Icons.newspaper
                      : relation.relationType == EntityRelationType.ownsProperty
                      ? Icons.home_work_outlined
                      : Icons.link,
                ),
                title: Text(related.name),
                subtitle: Text(
                  [
                    if (relation.relationDetail?.isNotEmpty ?? false)
                      relation.relationDetail!,
                    _relationLabel(relation.relationType, isArabic),
                    if (relation.validFrom != null || relation.validTo != null)
                      '${relation.validFrom ?? '?'} – ${relation.validTo ?? '?'}',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => WealthProfilePage(
                      entityId: related.id,
                      database: widget.database,
                    ),
                  ),
                ),
              ),
            ),
      for (final relation in relations)
        if (relation.sourceId != null)
          if (data.sources[relation.sourceId] case final source?)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
              child: _SourceCitation(source: source, isArabic: isArabic),
            ),
    ];
  }

  double? _normalizedWorth(WeeklySnapshot snapshot) {
    final amount = snapshot.totalNetWorth;
    if (amount == null) return null;
    return snapshot.currencyUnit == 'USD_B' ? amount * 1000 : amount;
  }
}

class _WealthProfileData {
  const _WealthProfileData({
    required this.entity,
    required this.snapshots,
    required this.streams,
    required this.relations,
    required this.relatedEntities,
    required this.sources,
  });

  final WealthEntity entity;
  final List<WeeklySnapshot> snapshots;
  final List<IncomeStream> streams;
  final List<EntityRelation> relations;
  final Map<String, WealthEntity> relatedEntities;
  final Map<String, WealthSource> sources;
}

class _SourceCitation extends StatelessWidget {
  const _SourceCitation({required this.source, required this.isArabic});

  final WealthSource source;
  final bool isArabic;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isArabic ? 'المصدر: ${source.title}' : 'Source: ${source.title}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        if (source.url != null) SelectableText(source.url!),
        if (source.url == null)
          Text(
            isArabic ? 'إدخال محلي يدوي' : 'Entered manually on this device',
          ),
      ],
    ),
  );
}

class _DiversificationBar extends StatelessWidget {
  const _DiversificationBar({required this.streams});

  final List<IncomeStream> streams;

  static const _colors = [
    Color(0xFF38BDF8),
    Color(0xFF34D399),
    Color(0xFFFBBF24),
    Color(0xFFF472B6),
    Color(0xFFA78BFA),
    Color(0xFFFB7185),
    Color(0xFF2DD4BF),
  ];

  @override
  Widget build(BuildContext context) {
    final portions = streams
        .where((stream) => (stream.portfolioSharePercent ?? 0) > 0)
        .toList();
    if (portions.isEmpty) return const SizedBox.shrink();
    final total = portions.fold<double>(
      0,
      (sum, stream) => sum + stream.portfolioSharePercent!,
    );
    final denominator = math.max(100, total);
    final segments = [
      for (var index = 0; index < portions.length; index++)
        (
          stream: portions[index],
          color: _colors[index % _colors.length],
          flex: math.max(
            1,
            (portions[index].portfolioSharePercent! / denominator * 1000)
                .round(),
          ),
        ),
    ];
    final usedFlex = segments.fold<int>(0, (sum, item) => sum + item.flex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 16,
            child: Row(
              children: [
                for (final segment in segments)
                  Expanded(
                    flex: segment.flex,
                    child: ColoredBox(color: segment.color),
                  ),
                if (total < 100)
                  Expanded(
                    flex: math.max(1, 1000 - usedFlex),
                    child: ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final segment in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 10, color: segment.color),
                  const SizedBox(width: 4),
                  Text(
                    '${segment.stream.portfolioSharePercent!.toStringAsFixed(0)}% '
                    '${segment.stream.title}',
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _NetWorthChartPainter extends CustomPainter {
  const _NetWorthChartPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
  });

  final List<double?> values;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 12.0;
    final chart = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var line = 0; line < 4; line++) {
      final y = chart.top + chart.height * line / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    final finiteValues = values.whereType<double>().toList();
    if (finiteValues.length < 2) return;
    final minimum = finiteValues.reduce(math.min);
    final maximum = finiteValues.reduce(math.max);
    final range = maximum - minimum;
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value == null) continue;
      final x = values.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (values.length - 1);
      final normalized = range == 0 ? 0.5 : (value - minimum) / range;
      final y = chart.bottom - chart.height * normalized;
      points.add(Offset(x, y));
    }
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, linePaint);
    final dotPaint = Paint()..color = lineColor;
    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_NetWorthChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _NoRecords extends StatelessWidget {
  const _NoRecords(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text),
  );
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
      child: Text(label),
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

String _streamLabel(IncomeStreamType type, bool isArabic) => switch (type) {
  IncomeStreamType.salaryContract => isArabic ? 'عقود' : 'Contracts',
  IncomeStreamType.endorsementsAds => isArabic ? 'إعلانات' : 'Ads',
  IncomeStreamType.royaltiesStreaming => isArabic ? 'حقوق' : 'Royalties',
  IncomeStreamType.toursEvents => isArabic ? 'فعاليات' : 'Events',
  IncomeStreamType.businessEquity => isArabic ? 'أعمال' : 'Business',
  IncomeStreamType.realEstate => isArabic ? 'عقارات' : 'Real estate',
  IncomeStreamType.investmentsStocks => isArabic ? 'استثمارات' : 'Investments',
};

String _relationLabel(EntityRelationType type, bool isArabic) => switch (type) {
  EntityRelationType.ownsProperty => isArabic ? 'يمتلك' : 'Owns property',
  EntityRelationType.ownsStake => isArabic ? 'حصة في' : 'Stake in',
  EntityRelationType.sponsoredBy => isArabic ? 'برعاية' : 'Sponsored by',
  EntityRelationType.playsFor => isArabic ? 'يلعب لصالح' : 'Plays for',
  EntityRelationType.impactedByNews =>
    isArabic ? 'متأثر بالأخبار' : 'Impacted by news',
};

String _formatNetWorth(double value, String currencyUnit) {
  final millions = currencyUnit == 'USD_B' ? value * 1000 : value;
  final amount = millions.abs() >= 1000
      ? '${(millions / 1000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}B'
      : '${millions.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}M';
  return '\$$amount';
}
