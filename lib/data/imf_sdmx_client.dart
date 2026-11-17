import 'dart:convert';

import 'package:http/http.dart' as http;

/// Supported versions of the IMF's SDMX RESTful API.
enum ImfApiVersion {
  v21('2.1'),
  v30('3.0');

  const ImfApiVersion(this.label);

  final String label;

  static ImfApiVersion parse(String value) => ImfApiVersion.values.firstWhere(
    (version) => version.label == value,
    orElse: () => throw FormatException('Unknown SDMX API version: $value'),
  );
}

/// Base URLs of the IMF's SDMX RESTful APIs.
const String imfSdmxBaseUrl = 'https://api.imf.org/external/sdmx/2.1';
const String imfSdmxV30BaseUrl = 'https://api.imf.org/external/sdmx/3.0';

/// A single observation returned by an SDMX data query.
class ImfObservationValue {
  const ImfObservationValue({required this.period, required this.value});

  final String period;
  final double value;
}

/// One series (one combination of series dimensions) in an SDMX data message.
class ImfSeries {
  const ImfSeries({
    required this.dimensions,
    required this.dimensionNames,
    required this.observations,
  });

  /// Dimension id -> selected code, e.g. `COUNTRY -> USA`.
  final Map<String, String> dimensions;

  /// Dimension id -> human readable code name, e.g. `COUNTRY -> United States`.
  final Map<String, String> dimensionNames;

  final List<ImfObservationValue> observations;

  String code(String dimensionId) => dimensions[dimensionId] ?? '';

  String name(String dimensionId) =>
      dimensionNames[dimensionId] ?? code(dimensionId);

  String get key => dimensions.entries.map((entry) => entry.value).join('.');
}

/// Parsed content of an SDMX-JSON data message.
class ImfDataMessage {
  const ImfDataMessage({
    required this.name,
    required this.description,
    required this.prepared,
    required this.senderId,
    required this.series,
  });

  final String? name;
  final String? description;
  final String? prepared;
  final String? senderId;
  final List<ImfSeries> series;
}

class ImfApiException implements Exception {
  const ImfApiException(this.statusCode, this.uri, this.message);

  final int statusCode;
  final Uri uri;
  final String message;

  @override
  String toString() => 'IMF API request failed ($statusCode): $message';
}

/// Client for the IMF SDMX 2.1 and 3.0 RESTful APIs.
///
/// 2.1 remains the default. 3.0 uses context-aware paths and a different
/// JSON envelope, both normalized into [ImfDataMessage]. Structure,
/// availability, and (for 3.0) metadata queries return decoded JSON maps.
class ImfSdmxClient {
  ImfSdmxClient({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.version = ImfApiVersion.v21,
  })  : _client = client ?? http.Client(),
        baseUrl = baseUrl ??
            (version == ImfApiVersion.v30
                ? imfSdmxV30BaseUrl
                : imfSdmxBaseUrl);

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;
  final ImfApiVersion version;

  /// Returns a client for another API version, reusing the same HTTP client.
  ImfSdmxClient forVersion(ImfApiVersion target) => target == version
      ? this
      : ImfSdmxClient(
          client: _client,
          baseUrl: target == ImfApiVersion.v30
              ? imfSdmxV30BaseUrl
              : imfSdmxBaseUrl,
          timeout: timeout,
          version: target,
        );

  Uri dataUri({
    required String flowRef,
    required String key,
    String? providerRef,
    String? startPeriod,
    String? endPeriod,
    String? updatedAfter,
    int? firstNObservations,
    int? lastNObservations,
    String dimensionAtObservation = 'TIME_PERIOD',
    String detail = 'dataonly',
    bool includeHistory = false,
  }) {
    final segments = version == ImfApiVersion.v21
        ? <String>[
            'data',
            _pathSegment(flowRef),
            _pathSegment(key),
            if (providerRef != null) _pathSegment(providerRef),
          ]
        : <String>[
            'data',
            'dataflow',
            ..._splitFlowRef(flowRef),
            _pathSegment(key),
          ];
    return _withQuery(
      segments,
      <String, Object?>{
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'updatedAfter': updatedAfter,
        'firstNObservations': firstNObservations,
        'lastNObservations': lastNObservations,
        'dimensionAtObservation': dimensionAtObservation,
        'detail': detail,
        'includeHistory': includeHistory,
      },
    );
  }

  Uri structureUri({
    required String structureType,
    String? agencyID,
    String? resourceID,
    String? versionId,
    String? itemID,
    String references = 'none',
    String detail = 'referencestubs',
  }) {
    final segments = <String>[
      if (version == ImfApiVersion.v30) 'structure',
      _pathSegment(structureType),
      if (agencyID != null) _pathSegment(agencyID),
      if (resourceID != null) _pathSegment(resourceID),
      if (versionId != null) _pathSegment(versionId),
      if (itemID != null) _pathSegment(itemID),
    ];
    return _withQuery(
      segments,
      <String, Object?>{
        'references': references,
        'detail': detail,
      },
    );
  }

  Uri availabilityUri({
    required String flowRef,
    required String key,
    required String providerRef,
    required String componentID,
    String? startPeriod,
    String? endPeriod,
    String? updatedAfter,
    String? mode,
    String? references,
  }) {
    final segments = version == ImfApiVersion.v21
        ? <String>[
            'availableconstraint',
            _pathSegment(flowRef),
            _pathSegment(key),
            _pathSegment(providerRef),
            _pathSegment(componentID),
          ]
        : <String>[
            'availability',
            'dataflow',
            ..._splitFlowRef(flowRef),
            _pathSegment(key),
            _pathSegment(componentID),
          ];
    return _withQuery(
      segments,
      <String, Object?>{
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'updatedAfter': updatedAfter,
        'mode': mode,
        'references': references,
      },
    );
  }

  /// `GET /metadata/structure/{structureType}/...` (3.0 only).
  Uri metadataStructureUri({
    required String structureType,
    String? agencyID,
    String? resourceID,
    String? versionId,
    String? itemID,
  }) {
    _requireV30('Structure metadata');
    return _withQuery(
      <String>[
        'metadata',
        'structure',
        _pathSegment(structureType),
        if (agencyID != null) _pathSegment(agencyID),
        if (resourceID != null) _pathSegment(resourceID),
        if (versionId != null) _pathSegment(versionId),
        if (itemID != null) _pathSegment(itemID),
      ],
      const <String, Object?>{},
    );
  }

  /// `GET /metadata/metadataflow/{agencyID}/{resourceID}/{version}/{providerID}`.
  Uri metadataFlowUri({
    required String agencyID,
    required String resourceID,
    String? versionId,
    String providerId = 'all',
  }) {
    _requireV30('Metadata flow');
    return _withQuery(
      <String>[
        'metadata',
        'metadataflow',
        _pathSegment(agencyID),
        _pathSegment(resourceID),
        if (versionId != null) _pathSegment(versionId),
        _pathSegment(providerId),
      ],
      const <String, Object?>{},
    );
  }

  /// `GET /metadata/metadataset/{providerID}/{resourceID}/{version}`.
  Uri metaDataSetUri({
    required String providerId,
    required String resourceID,
    String? versionId,
  }) {
    _requireV30('Metadata set');
    return _withQuery(
      <String>[
        'metadata',
        'metadataset',
        _pathSegment(providerId),
        _pathSegment(resourceID),
        if (versionId != null) _pathSegment(versionId),
      ],
      const <String, Object?>{},
    );
  }

  Future<ImfDataMessage> fetchData({
    required String flowRef,
    required String key,
    String? providerRef,
    String? startPeriod,
    String? endPeriod,
    String? updatedAfter,
    int? firstNObservations,
    int? lastNObservations,
    String dimensionAtObservation = 'TIME_PERIOD',
    String detail = 'dataonly',
    bool includeHistory = false,
  }) async {
    final uri = dataUri(
      flowRef: flowRef,
      key: key,
      providerRef: providerRef,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      updatedAfter: updatedAfter,
      firstNObservations: firstNObservations,
      lastNObservations: lastNObservations,
      dimensionAtObservation: dimensionAtObservation,
      detail: detail,
      includeHistory: includeHistory,
    );
    return parseDataMessage(await _getJson(uri), version: version);
  }

  Future<Map<String, dynamic>> fetchStructure({
    required String structureType,
    String? agencyID,
    String? resourceID,
    String? versionId,
    String? itemID,
    String references = 'none',
    String detail = 'referencestubs',
  }) {
    return _getJson(structureUri(
      structureType: structureType,
      agencyID: agencyID,
      resourceID: resourceID,
      versionId: versionId,
      itemID: itemID,
      references: references,
      detail: detail,
    ));
  }

  Future<Map<String, dynamic>> fetchAvailability({
    required String flowRef,
    required String key,
    required String providerRef,
    required String componentID,
    String? startPeriod,
    String? endPeriod,
    String? updatedAfter,
    String? mode,
    String? references,
  }) {
    return _getJson(availabilityUri(
      flowRef: flowRef,
      key: key,
      providerRef: providerRef,
      componentID: componentID,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      updatedAfter: updatedAfter,
      mode: mode,
      references: references,
    ));
  }

  Future<Map<String, dynamic>> fetchMetadataStructure({
    required String structureType,
    String? agencyID,
    String? resourceID,
    String? versionId,
    String? itemID,
  }) {
    return _getJson(metadataStructureUri(
      structureType: structureType,
      agencyID: agencyID,
      resourceID: resourceID,
      versionId: versionId,
      itemID: itemID,
    ));
  }

  Future<Map<String, dynamic>> fetchMetadataFlow({
    required String agencyID,
    required String resourceID,
    String? versionId,
    String providerId = 'all',
  }) {
    return _getJson(metadataFlowUri(
      agencyID: agencyID,
      resourceID: resourceID,
      versionId: versionId,
      providerId: providerId,
    ));
  }

  Future<Map<String, dynamic>> fetchMetaDataSet({
    required String providerId,
    required String resourceID,
    String? versionId,
  }) {
    return _getJson(metaDataSetUri(
      providerId: providerId,
      resourceID: resourceID,
      versionId: versionId,
    ));
  }

  /// Exposed for tests that provide a recorded SDMX-JSON payload.
  ImfDataMessage parsePayload(String payload, {ImfApiVersion? version}) =>
      parseDataMessage(
        jsonDecode(payload) as Object?,
        version: version ?? this.version,
      );

  Uri _withQuery(List<String> segments, Map<String, Object?> query) {
    final path = <String>[baseUrl.trimRight(), ...segments].join('/');
    final parameters = <String, String>{};
    query.forEach((key, value) {
      if (value != null) parameters[key] = '$value';
    });
    final encoded = parameters.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return Uri.parse(encoded.isEmpty ? path : '$path?$encoded');
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw ImfApiException(
        response.statusCode,
        uri,
        utf8.decode(response.bodyBytes, allowMalformed: true).trim(),
      );
    }
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('IMF response must be a JSON object.');
    }
    final data = decoded['data'];
    return data is Map<String, dynamic> ? data : decoded;
  }

  void _requireV30(String operation) {
    if (version != ImfApiVersion.v30) {
      throw UnsupportedError('$operation requires SDMX 3.0.');
    }
  }
}

/// Parses compact SDMX-JSON from either 2.1 or 3.0 into a common model.
///
/// 2.1: `{ header, dataSets, structure }`
/// 3.0: `{ meta, data: { dataSets, structures } }`, where each data set's
/// `structure` is an index into `structures`.
ImfDataMessage parseDataMessage(
  Object? decoded, {
  ImfApiVersion version = ImfApiVersion.v21,
}) {
  final root = _asMap(_unwrapDataMessage(decoded), 'data message');
  final dataSets = _list(root['dataSets']);
  final structures = _list(root['structures']);

  Map<String, dynamic>? sharedStructure;
  if (root['structure'] is Map<String, dynamic>) {
    sharedStructure = root['structure']! as Map<String, dynamic>;
  } else if (structures.isNotEmpty) {
    sharedStructure = _asMap(structures.first, 'structure');
  }
  if (sharedStructure == null) {
    throw FormatException('SDMX ${version.label} data message has no structure.');
  }

  final parsedStructures = <int, _ParsedStructure>{};
  final shared = _parseStructure(sharedStructure);
  _ParsedStructure structureFor(Map<String, dynamic> dataSet) {
    final reference = dataSet['structure'];
    if (reference is int &&
        reference >= 0 &&
        reference < structures.length) {
      return parsedStructures.putIfAbsent(
        reference,
        () => _parseStructure(_asMap(structures[reference], 'structure')),
      );
    }
    if (reference is Map<String, dynamic>) {
      return _parseStructure(reference);
    }
    return shared;
  }

  final header = root['header'] is Map<String, dynamic>
      ? root['header']! as Map<String, dynamic>
      : const <String, dynamic>{};
  final sender = header['sender'] is Map<String, dynamic>
      ? header['sender']! as Map<String, dynamic>
      : const <String, dynamic>{};
  final series = <ImfSeries>[];

  for (final dataSet in dataSets) {
    final dataSetMap = _asMap(dataSet, 'dataSet');
    final structure = structureFor(dataSetMap);
    final rawSeries = dataSetMap['series'];
    if (rawSeries is Map<String, dynamic>) {
      for (final entry in rawSeries.entries) {
        final positions = entry.key.split(':');
        final dimensionsByCode = <String, String>{};
        final namesByCode = <String, String>{};
        for (final dimension in structure.seriesDimensions) {
          final index = dimension.keyPosition;
          final rawPosition = index < positions.length ? positions[index] : null;
          final selected = _selectDimensionValue(
            dimension.values,
            rawPosition,
          );
          dimensionsByCode[dimension.id] = selected.id;
          namesByCode[dimension.id] = selected.name;
        }
        series.add(_parseSeries(
          _asMap(entry.value, 'series'),
          dimensionsByCode,
          namesByCode,
          structure.timeValues,
        ));
      }
    } else if (dataSetMap['observations'] is Map<String, dynamic>) {
      // Flat (AllDimensions) payload: a single series with dataset dimensions.
      final dimensionsByCode = <String, String>{};
      final namesByCode = <String, String>{};
      for (final dimension in structure.datasetDimensions) {
        if (dimension.values.isEmpty) continue;
        dimensionsByCode[dimension.id] = dimension.values.first.id;
        namesByCode[dimension.id] = dimension.values.first.name;
      }
      series.add(_parseSeries(
        dataSetMap,
        dimensionsByCode,
        namesByCode,
        structure.timeValues,
      ));
    }
  }

  // `version` is part of the public signature so callers can document the
  // payload source; both envelopes are handled structurally above.
  return ImfDataMessage(
    name: shared.name,
    description: shared.description,
    prepared: _optionalString(header['prepared']),
    senderId: _optionalString(sender['id']),
    series: series,
  );
}

_ParsedStructure _parseStructure(Map<String, dynamic> structure) {
  final dimensions = structure['dimensions'] is Map<String, dynamic>
      ? structure['dimensions']! as Map<String, dynamic>
      : const <String, dynamic>{};
  final seriesDimensions = _dimensionList(dimensions['series']);
  final observationDimensions = _dimensionList(dimensions['observation']);
  final timeDimension = observationDimensions.firstWhere(
    (dimension) =>
        dimension.role == 'time' || dimension.id == 'TIME_PERIOD',
    orElse: () => observationDimensions.isEmpty
        ? const _ImfDimension(id: 'TIME_PERIOD', keyPosition: 0)
        : observationDimensions.first,
  );
  return _ParsedStructure(
    name: _optionalString(structure['name']),
    description: _optionalString(structure['description']),
    seriesDimensions: seriesDimensions,
    datasetDimensions: _dimensionList(dimensions['dataset']),
    timeValues: timeDimension.values,
  );
}

ImfSeries _parseSeries(
  Map<String, dynamic> raw,
  Map<String, String> dimensions,
  Map<String, String> dimensionNames,
  List<_ImfCode> timeValues,
) {
  final observations = <ImfObservationValue>[];
  final rawObservations = raw['observations'];
  if (rawObservations is Map<String, dynamic>) {
    for (final entry in rawObservations.entries) {
      final rawValue = entry.value;
      final value = rawValue is List && rawValue.isNotEmpty
          ? double.tryParse('${rawValue.first}')
          : null;
      if (value == null || value.isNaN || value.isInfinite) continue;
      final index = int.tryParse(entry.key);
      final period = index != null && index < timeValues.length
          ? timeValues[index].id
          : entry.key;
      observations.add(ImfObservationValue(period: period, value: value));
    }
  }
  observations.sort((a, b) => a.period.compareTo(b.period));
  return ImfSeries(
    dimensions: dimensions,
    dimensionNames: dimensionNames,
    observations: observations,
  );
}

_ImfCode _selectDimensionValue(List<_ImfCode> values, String? rawPosition) {
  // Series keys are positional indices into each dimension's values array
  // (e.g. "1:0:0:0:0"), not the codes themselves.
  final valueIndex = int.tryParse(rawPosition ?? '');
  if (valueIndex != null && valueIndex >= 0 && valueIndex < values.length) {
    return values[valueIndex];
  }
  return values.firstWhere(
    (item) => item.id == rawPosition,
    orElse: () => _ImfCode(id: rawPosition ?? '', name: rawPosition ?? ''),
  );
}

Object? _unwrapDataMessage(Object? decoded) {
  if (decoded is Map<String, dynamic> &&
      decoded['dataSets'] == null &&
      decoded['data'] is Map<String, dynamic>) {
    return decoded['data'];
  }
  return decoded;
}

List<String> _splitFlowRef(String flowRef) {
  final parts = flowRef
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length == 2) return <String>[...parts, 'latest'];
  if (parts.length != 3) {
    throw ArgumentError.value(
      flowRef,
      'flowRef',
      'Expected agency,resource[,version] for SDMX 3.0.',
    );
  }
  return parts;
}

String _pathSegment(String value) => Uri.encodeComponent(value);

Map<String, dynamic> _asMap(Object? value, String label) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('Expected $label to be a JSON object.');
  }
  return value;
}

List<Object?> _list(Object? value) =>
    value is List ? value : const <Object?>[];

String? _optionalString(Object? value) => value is String ? value : null;

List<_ImfDimension> _dimensionList(Object? value) {
  final dimensions = <_ImfDimension>[];
  for (final rawDimension in _list(value)) {
    final dimension = _asMap(rawDimension, 'dimension');
    dimensions.add(_ImfDimension(
      id: '${dimension['id'] ?? ''}',
      name: _optionalString(dimension['name']),
      keyPosition: (dimension['keyPosition'] as num?)?.toInt() ?? 0,
      role: _dimensionRole(dimension['role'] ?? dimension['roles']),
      values: _valueList(dimension['values']),
    ));
  }
  return dimensions..sort((a, b) => a.keyPosition.compareTo(b.keyPosition));
}

String? _dimensionRole(Object? value) {
  if (value is String) return value;
  if (value is List) {
    for (final item in value) {
      if (item is String) return item;
    }
  }
  return null;
}

List<_ImfCode> _valueList(Object? value) {
  final codes = <_ImfCode>[];
  for (final rawValue in _list(value)) {
    final code = _asMap(rawValue, 'dimension value');
    final id = code['id'] ?? code['value'];
    codes.add(_ImfCode(
      id: '$id',
      name: _optionalString(code['name']) ??
          _optionalString(code['value']) ??
          '$id',
    ));
  }
  return codes;
}

class _ParsedStructure {
  const _ParsedStructure({
    this.name,
    this.description,
    required this.seriesDimensions,
    required this.datasetDimensions,
    required this.timeValues,
  });

  final String? name;
  final String? description;
  final List<_ImfDimension> seriesDimensions;
  final List<_ImfDimension> datasetDimensions;
  final List<_ImfCode> timeValues;
}

class _ImfDimension {
  const _ImfDimension({
    required this.id,
    this.name,
    required this.keyPosition,
    this.role,
    this.values = const <_ImfCode>[],
  });

  final String id;
  final String? name;
  final int keyPosition;
  final String? role;
  final List<_ImfCode> values;
}

class _ImfCode {
  const _ImfCode({required this.id, required this.name});

  final String id;
  final String name;
}
