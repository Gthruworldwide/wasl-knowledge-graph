import 'package:flutter/material.dart';

import '../data/wealth_mutations.dart';
import '../data/wealth_models.dart';

Future<EntityDraft?> showEntityEditor(
  BuildContext context, {
  required bool isArabic,
  WealthEntity? entity,
  WealthSource? source,
  List<IncomeStream> incomeStreams = const [],
  List<EntityRelation> links = const [],
  List<WealthEntity> linkTargets = const [],
}) => showModalBottomSheet<EntityDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _EntityEditorSheet(
    isArabic: isArabic,
    entity: entity,
    source: source,
    incomeStreams: incomeStreams,
    links: links,
    linkTargets: linkTargets,
  ),
);

class _EntityEditorSheet extends StatefulWidget {
  const _EntityEditorSheet({
    required this.isArabic,
    required this.entity,
    required this.source,
    required this.incomeStreams,
    required this.links,
    required this.linkTargets,
  });

  final bool isArabic;
  final WealthEntity? entity;
  final WealthSource? source;
  final List<IncomeStream> incomeStreams;
  final List<EntityRelation> links;
  final List<WealthEntity> linkTargets;

  @override
  State<_EntityEditorSheet> createState() => _EntityEditorSheetState();
}

class _EntityEditorSheetState extends State<_EntityEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _subtitle = TextEditingController();
  final _origin = TextEditingController();
  final _sourceTitle = TextEditingController();
  final _sourceUrl = TextEditingController();
  final _streams = <_StreamEditor>[];
  final _links = <EntityLinkDraft>[];
  EntityCategory? _category;

  bool get _isEditing => widget.entity != null;

  @override
  void initState() {
    super.initState();
    final entity = widget.entity;
    _category = entity?.category;
    _name.text = entity?.name ?? '';
    _subtitle.text = entity?.subtitle ?? '';
    _origin.text = entity?.nationalityOrOrigin ?? '';
    _sourceTitle.text = widget.isArabic ? 'إدخال يدوي' : 'Manual entry';
    if (widget.source != null) {
      _sourceTitle.text = widget.source!.title;
      _sourceUrl.text = widget.source!.url ?? '';
    }
    for (final stream in widget.incomeStreams) {
      _streams.add(_StreamEditor.fromStream(stream));
    }
    for (final relation in widget.links) {
      _links.add(
        EntityLinkDraft(
          id: relation.id,
          targetId: relation.toEntityId,
          relationType: relation.relationType,
          relationDetail: relation.relationDetail,
        ),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _subtitle.dispose();
    _origin.dispose();
    _sourceTitle.dispose();
    _sourceUrl.dispose();
    for (final stream in _streams) {
      stream.dispose();
    }
    super.dispose();
  }

  void _addStream() {
    setState(() {
      _streams.add(_StreamEditor(type: IncomeStreamType.salaryContract));
    });
  }

  void _removeStream(int index) {
    setState(() {
      _streams.removeAt(index).dispose();
    });
  }

  Future<void> _addLink() async {
    if (widget.linkTargets.isEmpty) return;
    var targetId = widget.linkTargets.first.id;
    var relationType = EntityRelationType.ownsProperty;
    final detail = TextEditingController();
    final link = await showDialog<EntityLinkDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            widget.isArabic ? 'ربط أصل أو شركة' : 'Link an asset or company',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: targetId,
                  decoration: InputDecoration(
                    labelText: widget.isArabic ? 'الكيان المرتبط' : 'Entity',
                  ),
                  items: [
                    for (final target in widget.linkTargets)
                      DropdownMenuItem(
                        value: target.id,
                        child: Text(target.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => targetId = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EntityRelationType>(
                  initialValue: relationType,
                  decoration: InputDecoration(
                    labelText: widget.isArabic ? 'نوع العلاقة' : 'Relation',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: EntityRelationType.ownsProperty,
                      child: Text(
                        widget.isArabic ? 'يمتلك عقارًا' : 'Owns property',
                      ),
                    ),
                    DropdownMenuItem(
                      value: EntityRelationType.ownsStake,
                      child: Text(widget.isArabic ? 'يمتلك حصة' : 'Owns stake'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => relationType = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detail,
                  decoration: InputDecoration(
                    labelText: widget.isArabic
                        ? 'تفاصيل العلاقة (اختياري)'
                        : 'Relation detail (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(widget.isArabic ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                EntityLinkDraft(
                  targetId: targetId,
                  relationType: relationType,
                  relationDetail: _nullable(detail.text),
                ),
              ),
              child: Text(widget.isArabic ? 'ربط' : 'Link'),
            ),
          ],
        ),
      ),
    );
    detail.dispose();
    if (link != null) setState(() => _links.add(link));
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      EntityDraft(
        category: _category!,
        name: _name.text.trim(),
        subtitle: _nullable(_subtitle.text),
        nationalityOrOrigin: _nullable(_origin.text),
        sourceTitle: _isEditing ? null : _sourceTitle.text.trim(),
        sourceUrl: _isEditing ? null : _nullable(_sourceUrl.text),
        incomeStreams: [
          for (final stream in _streams)
            IncomeStreamDraft(
              id: stream.id,
              streamType: stream.type,
              title: stream.title.text.trim(),
              estimatedAnnualValue: _numberOrNull(stream.annualValue.text),
              portfolioSharePercent: _numberOrNull(stream.share.text),
            ),
        ],
        links: List.unmodifiable(_links),
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
                  _isEditing
                      ? (isArabic ? 'تعديل الكيان' : 'Edit entity')
                      : (isArabic ? 'كيان جديد' : 'New entity'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<EntityCategory>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: isArabic ? 'الفئة' : 'Category',
                  ),
                  items: [
                    for (final category in EntityCategory.values)
                      DropdownMenuItem(
                        value: category,
                        child: Text(_categoryLabel(category, isArabic)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _category = value),
                  validator: (value) =>
                      value == null ? _requiredMessage(isArabic) : null,
                ),
                _field(_name, isArabic ? 'الاسم' : 'Name', required: true),
                _field(
                  _subtitle,
                  isArabic ? 'وصف مختصر (اختياري)' : 'Subtitle (optional)',
                ),
                _field(
                  _origin,
                  isArabic ? 'الدولة أو المنشأ (اختياري)' : 'Origin (optional)',
                ),
                if (!_isEditing) ...[
                  _field(
                    _sourceTitle,
                    isArabic ? 'عنوان المصدر' : 'Source title',
                    required: true,
                  ),
                  _field(
                    _sourceUrl,
                    isArabic
                        ? 'رابط المصدر (اختياري)'
                        : 'Source URL (optional)',
                    keyboardType: TextInputType.url,
                    validator: _urlValidator(isArabic),
                  ),
                ] else if (widget.source != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      isArabic
                          ? 'المصدر الحالي: ${widget.source!.title}'
                          : 'Current source: ${widget.source!.title}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isArabic ? 'مصادر الدخل' : 'Income streams',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addStream,
                      icon: const Icon(Icons.add),
                      label: Text(isArabic ? 'إضافة مصدر' : 'Add stream'),
                    ),
                  ],
                ),
                if (_streams.isEmpty)
                  Text(
                    isArabic
                        ? 'لا توجد مصادر دخل بعد. أضف مصدرًا وحدد نسبته من المحفظة.'
                        : 'No income streams yet. Add one and set its portfolio share.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                for (var index = 0; index < _streams.length; index++)
                  _buildStreamCard(index, isArabic),
                const SizedBox(height: 20),
                Text(
                  isArabic ? 'الممتلكات والحصص المرتبطة' : 'Linked holdings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                if (_links.isEmpty)
                  Text(
                    isArabic
                        ? 'لا توجد روابط بعد. اربط عقارًا أو شركة موجودة.'
                        : 'No links yet. Connect an existing property or company.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (var index = 0; index < _links.length; index++)
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: ListTile(
                        leading: Icon(
                          _links[index].relationType ==
                                  EntityRelationType.ownsProperty
                              ? Icons.home_work_outlined
                              : Icons.pie_chart_outline,
                        ),
                        title: Text(_targetName(_links[index].targetId)),
                        subtitle: Text(
                          [
                            if (_links[index].relationDetail?.isNotEmpty ??
                                false)
                              _links[index].relationDetail!,
                            _relationLabel(
                              _links[index].relationType,
                              isArabic,
                            ),
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: isArabic ? 'إزالة الرابط' : 'Remove link',
                          onPressed: () =>
                              setState(() => _links.removeAt(index)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.linkTargets.isEmpty ? null : _addLink,
                  icon: const Icon(Icons.add_link),
                  label: Text(
                    isArabic
                        ? 'ربط عقار أو شركة موجودة'
                        : 'Link an existing property or company',
                  ),
                ),
                if (widget.linkTargets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      isArabic
                          ? 'أضف كيانًا من نوع الممتلكات أو الشركات أولًا لتتمكن من ربطه.'
                          : 'Add a property or company entity first so it can be linked here.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _save,
                  child: Text(
                    _isEditing
                        ? (isArabic ? 'حفظ التعديلات' : 'Save changes')
                        : (isArabic ? 'حفظ الكيان' : 'Save entity'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreamCard(int index, bool isArabic) {
    final stream = _streams[index];
    return Card(
      key: ObjectKey(stream),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<IncomeStreamType>(
                    initialValue: stream.type,
                    decoration: InputDecoration(
                      labelText: isArabic ? 'نوع المصدر' : 'Stream type',
                    ),
                    items: [
                      for (final type in IncomeStreamType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(_streamLabel(type, isArabic)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => stream.type = value);
                      }
                    },
                  ),
                ),
                IconButton(
                  tooltip: isArabic ? 'حذف المصدر' : 'Remove stream',
                  onPressed: () => _removeStream(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            _field(stream.title, isArabic ? 'الوصف' : 'Title', required: true),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    stream.annualValue,
                    isArabic
                        ? 'القيمة السنوية (مليون دولار)'
                        : 'Annual value (USD M)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _numberValidator(isArabic, maximum: null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    stream.share,
                    isArabic ? 'نسبة المحفظة %' : 'Portfolio share %',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _numberValidator(isArabic, maximum: 100),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        if (required && (value?.trim().isEmpty ?? true)) {
          return _requiredMessage(widget.isArabic);
        }
        return validator?.call(value);
      },
    ),
  );

  String _targetName(String id) {
    for (final target in widget.linkTargets) {
      if (target.id == id) return target.name;
    }
    return id;
  }
}

class _StreamEditor {
  _StreamEditor({
    this.id,
    required this.type,
    String title = '',
    String annualValue = '',
    String share = '',
  }) : title = TextEditingController(text: title),
       annualValue = TextEditingController(text: annualValue),
       share = TextEditingController(text: share);

  factory _StreamEditor.fromStream(IncomeStream stream) => _StreamEditor(
    id: stream.id,
    type: stream.streamType,
    title: stream.title,
    annualValue: stream.estimatedAnnualValue?.toString() ?? '',
    share: stream.portfolioSharePercent?.toString() ?? '',
  );

  final String? id;
  IncomeStreamType type;
  final TextEditingController title;
  final TextEditingController annualValue;
  final TextEditingController share;

  void dispose() {
    title.dispose();
    annualValue.dispose();
    share.dispose();
  }
}

String? _nullable(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

double? _numberOrNull(String value) =>
    value.trim().isEmpty ? null : double.tryParse(value.trim());

String _requiredMessage(bool isArabic) =>
    isArabic ? 'هذا الحقل مطلوب' : 'Required';

String? Function(String?)? _urlValidator(bool isArabic) => (value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty) {
    return isArabic
        ? 'أدخل رابط HTTP أو HTTPS صالحًا'
        : 'Enter a valid http or https URL';
  }
  return null;
};

String? Function(String?)? _numberValidator(
  bool isArabic, {
  required double? maximum,
}) => (value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final parsed = double.tryParse(normalized);
  if (parsed == null || !parsed.isFinite || parsed < 0) {
    return isArabic ? 'أدخل رقمًا صالحًا' : 'Enter a valid number';
  }
  if (maximum != null && parsed > maximum) {
    return isArabic ? 'يجب ألا يتجاوز 100' : 'Must be 100 or less';
  }
  return null;
};

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
