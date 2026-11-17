import 'imf_sdmx_client.dart';

/// IMF CPI dataflow and key components used by Wasl's local CPI import.
class ImfCpiCatalog {
  static const String agencyId = 'IMF.STA';
  static const String resourceId = 'CPI';
  static const String flowVersion30 = '5.0.0';

  /// 2.1 flow reference: agency,resource.
  static const String flowRef = '$agencyId,$resourceId';

  /// 3.0 data queries include the dataflow version in the flow reference.
  static String flowRefFor(ImfApiVersion version) => version == ImfApiVersion.v30
      ? '$agencyId,$resourceId,$flowVersion30'
      : flowRef;

  static const String providerRef = 'all';
  static const String indexType = 'CPI';
  static const String expenditureCategory = '_T'; // All items
  static const String transformation = 'YOY_PCH_PA_PT';
  static const String frequency = 'M';
  static const String unit = 'PERCENT';
  static const String apiHelpUrl =
      'https://data.imf.org/en/datasets/IMF.STA:CPI';

  /// Builds `COUNTRY.CPI._T.YOY_PCH_PA_PT.M`; `+` selects several countries.
  static String keyFor(Iterable<String> countryCodes) =>
      '${countryCodes.join('+')}.$indexType.$expenditureCategory.'
      '$transformation.$frequency';

  /// Human-readable fallback URL. The repository records the exact generated
  /// request URI from [ImfSdmxClient.dataUri] for provenance.
  static String sourceUrl(
    List<String> countryCodes, {
    int startYear = 2022,
    ImfApiVersion version = ImfApiVersion.v21,
  }) {
    final key = keyFor(countryCodes);
    if (version == ImfApiVersion.v30) {
      return '$imfSdmxV30BaseUrl/data/dataflow/$agencyId/$resourceId/'
          '$flowVersion30/$key'
          '?startPeriod=$startYear&dimensionAtObservation=TIME_PERIOD'
          '&detail=dataonly&includeHistory=false';
    }
    return '$imfSdmxBaseUrl/data/$flowRef/$key/$providerRef'
        '?startPeriod=$startYear&dimensionAtObservation=TIME_PERIOD'
        '&detail=dataonly&includeHistory=false';
  }

}

class ImfCountry {
  const ImfCountry({
    required this.code,
    required this.name,
    required this.arabicName,
  });

  final String code;
  final String name;
  final String arabicName;

  String label(bool isArabic) => isArabic ? arabicName : name;
}

/// Country codes verified against the IMF `CL_COUNTRY` codelist.
const List<ImfCountry> imfCpiCountries = [
  ImfCountry(
    code: 'USA',
    name: 'United States',
    arabicName: 'الولايات المتحدة',
  ),
  ImfCountry(
    code: 'GBR',
    name: 'United Kingdom',
    arabicName: 'المملكة المتحدة',
  ),
  ImfCountry(code: 'DEU', name: 'Germany', arabicName: 'ألمانيا'),
  ImfCountry(code: 'FRA', name: 'France', arabicName: 'فرنسا'),
  ImfCountry(code: 'ITA', name: 'Italy', arabicName: 'إيطاليا'),
  ImfCountry(code: 'ESP', name: 'Spain', arabicName: 'إسبانيا'),
  ImfCountry(code: 'JPN', name: 'Japan', arabicName: 'اليابان'),
  ImfCountry(code: 'CHN', name: 'China', arabicName: 'الصين'),
  ImfCountry(code: 'IND', name: 'India', arabicName: 'الهند'),
  ImfCountry(code: 'CAN', name: 'Canada', arabicName: 'كندا'),
  ImfCountry(code: 'AUS', name: 'Australia', arabicName: 'أستراليا'),
  ImfCountry(code: 'BRA', name: 'Brazil', arabicName: 'البرازيل'),
  ImfCountry(
    code: 'ZAF',
    name: 'South Africa',
    arabicName: 'جنوب أفريقيا',
  ),
  ImfCountry(
    code: 'SAU',
    name: 'Saudi Arabia',
    arabicName: 'السعودية',
  ),
  ImfCountry(
    code: 'ARE',
    name: 'United Arab Emirates',
    arabicName: 'الإمارات',
  ),
  ImfCountry(code: 'EGY', name: 'Egypt', arabicName: 'مصر'),
  ImfCountry(code: 'MAR', name: 'Morocco', arabicName: 'المغرب'),
  ImfCountry(code: 'TUR', name: 'Türkiye', arabicName: 'تركيا'),
  ImfCountry(
    code: 'KOR',
    name: 'South Korea',
    arabicName: 'كوريا الجنوبية',
  ),
  ImfCountry(code: 'SGP', name: 'Singapore', arabicName: 'سنغافورة'),
  ImfCountry(code: 'MEX', name: 'Mexico', arabicName: 'المكسيك'),
];

const List<String> defaultImfCountryCodes = [
  'USA',
  'GBR',
  'DEU',
  'JPN',
  'CHN',
  'SAU',
];

ImfCountry? imfCountry(String code) {
  for (final country in imfCpiCountries) {
    if (country.code == code) return country;
  }
  return null;
}
