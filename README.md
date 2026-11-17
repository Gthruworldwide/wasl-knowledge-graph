# Wasl (وصل)

Wasl is a standalone Flutter mobile app (`com.gthruworldwide.wasl.app`) and local-first knowledge graph. It has no connection to the legacy football app or its backend.

## Wealth data foundation

The version 3 SQLite database in `lib/data/wealth_database.dart` defines entities, weekly snapshots, income streams, relations, and sources. Entities and relations retain source links; relations also support optional valid-time ranges. `WealthDao` provides typed access and recalculates a snapshot's week-over-week percentage against the immediately preceding ISO week. The importer writes a complete bundle in a single transaction.

The general connected-knowledge screen remains the app's primary view. Open the wealth pilot using the insights icon. It provides category filters, sourced wealth cards and profiles, history charts, income diversification, and clickable holdings. Users can add a sourced entity manually or paste a v2.0 JSON bundle; the fictional sample is clearly labeled and imported only on explicit selection.

`assets/seed/weekly_bundle_v2.json` is a fictional example bundle. Its values and relationships are illustrative only, not claims about real people or organizations. It is bundled but is not automatically imported.

```dart
final db = WealthDatabase();
final summary = await WeeklyBundleImporter(db).importBundle(jsonText);
```

The importer accepts bundle version `2.0`; its source must be `JSON_IMPORT`. Re-importing the same bundle upserts its entities, snapshots, streams, and relations.

## Development

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

Both the general knowledge graph and wealth records are stored locally on the device. Wasl does not add synchronization, automatic data feeds, or AI explanations. The UI does not independently verify user-provided source URLs or imported claims.
