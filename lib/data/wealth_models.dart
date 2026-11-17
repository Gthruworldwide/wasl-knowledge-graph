enum EntityCategory {
  athlete,
  artist,
  businessFigure,
  company,
  propertyAsset,
  economicNews,
}

extension EntityCategoryValue on EntityCategory {
  String get value => switch (this) {
    EntityCategory.athlete => 'ATHLETE',
    EntityCategory.artist => 'ARTIST',
    EntityCategory.businessFigure => 'BUSINESS_FIGURE',
    EntityCategory.company => 'COMPANY',
    EntityCategory.propertyAsset => 'PROPERTY_ASSET',
    EntityCategory.economicNews => 'ECONOMIC_NEWS',
  };

  static EntityCategory parse(String value) => EntityCategory.values.firstWhere(
    (category) => category.value == value,
    orElse: () => throw FormatException('Unknown entity category: $value'),
  );
}

enum SourceType { manual, jsonImport, rssFeed }

extension SourceTypeValue on SourceType {
  String get value => switch (this) {
    SourceType.manual => 'MANUAL',
    SourceType.jsonImport => 'JSON_IMPORT',
    SourceType.rssFeed => 'RSS_FEED',
  };

  static SourceType parse(String value) => SourceType.values.firstWhere(
    (type) => type.value == value,
    orElse: () => throw FormatException('Unknown source type: $value'),
  );
}

enum IncomeStreamType {
  salaryContract,
  endorsementsAds,
  royaltiesStreaming,
  toursEvents,
  businessEquity,
  realEstate,
  investmentsStocks,
}

extension IncomeStreamTypeValue on IncomeStreamType {
  String get value => switch (this) {
    IncomeStreamType.salaryContract => 'SALARY_CONTRACT',
    IncomeStreamType.endorsementsAds => 'ENDORSEMENTS_ADS',
    IncomeStreamType.royaltiesStreaming => 'ROYALTIES_STREAMING',
    IncomeStreamType.toursEvents => 'TOURS_EVENTS',
    IncomeStreamType.businessEquity => 'BUSINESS_EQUITY',
    IncomeStreamType.realEstate => 'REAL_ESTATE',
    IncomeStreamType.investmentsStocks => 'INVESTMENTS_STOCKS',
  };

  static IncomeStreamType parse(String value) =>
      IncomeStreamType.values.firstWhere(
        (type) => type.value == value,
        orElse: () => throw FormatException('Unknown income stream: $value'),
      );
}

enum EntityRelationType {
  ownsProperty,
  ownsStake,
  sponsoredBy,
  playsFor,
  impactedByNews,
}

extension EntityRelationTypeValue on EntityRelationType {
  String get value => switch (this) {
    EntityRelationType.ownsProperty => 'OWNS_PROPERTY',
    EntityRelationType.ownsStake => 'OWNS_STAKE',
    EntityRelationType.sponsoredBy => 'SPONSORED_BY',
    EntityRelationType.playsFor => 'PLAYS_FOR',
    EntityRelationType.impactedByNews => 'IMPACTED_BY_NEWS',
  };

  static EntityRelationType parse(String value) =>
      EntityRelationType.values.firstWhere(
        (type) => type.value == value,
        orElse: () => throw FormatException('Unknown relation type: $value'),
      );
}

class WealthEntity {
  const WealthEntity({
    required this.id,
    required this.category,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.sourceId,
    this.subtitle,
    this.nationalityOrOrigin,
    this.metadataJson = '{}',
  });

  final String id;
  final EntityCategory category;
  final String name;
  final String? subtitle;
  final String? nationalityOrOrigin;
  final String metadataJson;
  final String? sourceId;
  final String createdAt;
  final String updatedAt;

  Map<String, Object?> toRow() => {
    'id': id,
    'category': category.value,
    'name': name,
    'subtitle': subtitle,
    'nationality_or_origin': nationalityOrOrigin,
    'metadata_json': metadataJson,
    'source_id': sourceId,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory WealthEntity.fromRow(Map<String, Object?> row) => WealthEntity(
    id: row['id']! as String,
    category: EntityCategoryValue.parse(row['category']! as String),
    name: row['name']! as String,
    subtitle: row['subtitle'] as String?,
    nationalityOrOrigin: row['nationality_or_origin'] as String?,
    metadataJson: row['metadata_json']! as String,
    sourceId: row['source_id'] as String?,
    createdAt: row['created_at']! as String,
    updatedAt: row['updated_at']! as String,
  );
}

class WealthSource {
  const WealthSource({
    required this.id,
    required this.title,
    required this.sourceType,
    required this.lastSyncedAt,
    this.url,
  });

  final String id;
  final String title;
  final String? url;
  final SourceType sourceType;
  final String lastSyncedAt;

  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'url': url,
    'source_type': sourceType.value,
    'last_synced_at': lastSyncedAt,
  };

  factory WealthSource.fromRow(Map<String, Object?> row) => WealthSource(
    id: row['id']! as String,
    title: row['title']! as String,
    url: row['url'] as String?,
    sourceType: SourceTypeValue.parse(row['source_type']! as String),
    lastSyncedAt: row['last_synced_at']! as String,
  );
}

class WeeklySnapshot {
  const WeeklySnapshot({
    required this.id,
    required this.entityId,
    required this.weekIdentifier,
    required this.recordedAt,
    required this.currencyUnit,
    required this.sourceId,
    this.totalNetWorth,
    this.wowChangePercent,
    this.summaryNote,
  });

  final String id;
  final String entityId;
  final String weekIdentifier;
  final String recordedAt;
  final double? totalNetWorth;
  final String currencyUnit;
  final double? wowChangePercent;
  final String? summaryNote;
  final String sourceId;

  Map<String, Object?> toRow() => {
    'id': id,
    'entity_id': entityId,
    'week_identifier': weekIdentifier,
    'recorded_at': recordedAt,
    'total_net_worth': totalNetWorth,
    'currency_unit': currencyUnit,
    'wow_change_percent': wowChangePercent,
    'summary_note': summaryNote,
    'source_id': sourceId,
  };

  factory WeeklySnapshot.fromRow(Map<String, Object?> row) => WeeklySnapshot(
    id: row['id']! as String,
    entityId: row['entity_id']! as String,
    weekIdentifier: row['week_identifier']! as String,
    recordedAt: row['recorded_at']! as String,
    totalNetWorth: (row['total_net_worth'] as num?)?.toDouble(),
    currencyUnit: row['currency_unit']! as String,
    wowChangePercent: (row['wow_change_percent'] as num?)?.toDouble(),
    summaryNote: row['summary_note'] as String?,
    sourceId: row['source_id']! as String,
  );
}

class IncomeStream {
  const IncomeStream({
    required this.id,
    required this.entityId,
    required this.streamType,
    required this.title,
    required this.lastUpdatedWeek,
    this.estimatedAnnualValue,
    this.portfolioSharePercent,
  });

  final String id;
  final String entityId;
  final IncomeStreamType streamType;
  final String title;
  final double? estimatedAnnualValue;
  final double? portfolioSharePercent;
  final String lastUpdatedWeek;

  Map<String, Object?> toRow() => {
    'id': id,
    'entity_id': entityId,
    'stream_type': streamType.value,
    'title': title,
    'estimated_annual_value': estimatedAnnualValue,
    'portfolio_share_percent': portfolioSharePercent,
    'last_updated_week': lastUpdatedWeek,
  };

  factory IncomeStream.fromRow(Map<String, Object?> row) => IncomeStream(
    id: row['id']! as String,
    entityId: row['entity_id']! as String,
    streamType: IncomeStreamTypeValue.parse(row['stream_type']! as String),
    title: row['title']! as String,
    estimatedAnnualValue: (row['estimated_annual_value'] as num?)?.toDouble(),
    portfolioSharePercent: (row['portfolio_share_percent'] as num?)?.toDouble(),
    lastUpdatedWeek: row['last_updated_week']! as String,
  );
}

class EntityRelation {
  const EntityRelation({
    required this.id,
    required this.fromEntityId,
    required this.toEntityId,
    required this.relationType,
    this.sourceId,
    this.relationDetail,
    this.validFrom,
    this.validTo,
  });

  final String id;
  final String fromEntityId;
  final String toEntityId;
  final EntityRelationType relationType;
  final String? sourceId;
  final String? relationDetail;
  final String? validFrom;
  final String? validTo;

  Map<String, Object?> toRow() => {
    'id': id,
    'from_entity_id': fromEntityId,
    'to_entity_id': toEntityId,
    'relation_type': relationType.value,
    'relation_detail': relationDetail,
    'source_id': sourceId,
    'valid_from': validFrom,
    'valid_to': validTo,
  };

  factory EntityRelation.fromRow(Map<String, Object?> row) => EntityRelation(
    id: row['id']! as String,
    fromEntityId: row['from_entity_id']! as String,
    toEntityId: row['to_entity_id']! as String,
    relationType: EntityRelationTypeValue.parse(
      row['relation_type']! as String,
    ),
    relationDetail: row['relation_detail'] as String?,
    sourceId: row['source_id'] as String?,
    validFrom: row['valid_from'] as String?,
    validTo: row['valid_to'] as String?,
  );
}
