import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class WealthDatabase {
  WealthDatabase({DatabaseFactory? factory, this.databasePath})
    : _factory = factory ?? databaseFactory;

  final DatabaseFactory _factory;
  final String? databasePath;
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final path = databasePath ?? p.join(await getDatabasesPath(), 'wasl.db');
    final opened = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    final opened = _database;
    _database = null;
    if (opened != null) await opened.close();
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE entities (
        id TEXT PRIMARY KEY NOT NULL,
        category TEXT NOT NULL CHECK (category IN (
          'ATHLETE', 'ARTIST', 'BUSINESS_FIGURE', 'COMPANY',
          'PROPERTY_ASSET', 'ECONOMIC_NEWS'
        )),
        name TEXT NOT NULL,
        subtitle TEXT,
        nationality_or_origin TEXT,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        source_id TEXT REFERENCES sources(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_entities_name ON entities(name)');
    await db.execute(
      'CREATE INDEX idx_entities_category ON entities(category)',
    );
    await db.execute('''
      CREATE TABLE sources (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        url TEXT,
        source_type TEXT NOT NULL CHECK (source_type IN (
          'MANUAL', 'JSON_IMPORT', 'RSS_FEED'
        )),
        last_synced_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE weekly_snapshots (
        id TEXT PRIMARY KEY NOT NULL,
        entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
        week_identifier TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        total_net_worth REAL,
        currency_unit TEXT NOT NULL DEFAULT 'USD_M',
        wow_change_percent REAL,
        summary_note TEXT,
        source_id TEXT NOT NULL REFERENCES sources(id),
        UNIQUE(entity_id, week_identifier)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_snapshots_entity_week '
      'ON weekly_snapshots(entity_id, week_identifier)',
    );
    await db.execute('''
      CREATE TABLE income_streams (
        id TEXT PRIMARY KEY NOT NULL,
        entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
        stream_type TEXT NOT NULL CHECK (stream_type IN (
          'SALARY_CONTRACT', 'ENDORSEMENTS_ADS', 'ROYALTIES_STREAMING',
          'TOURS_EVENTS', 'BUSINESS_EQUITY', 'REAL_ESTATE',
          'INVESTMENTS_STOCKS'
        )),
        title TEXT NOT NULL,
        estimated_annual_value REAL,
        portfolio_share_percent REAL,
        last_updated_week TEXT NOT NULL,
        UNIQUE(entity_id, stream_type, title)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_income_entity ON income_streams(entity_id)',
    );
    await db.execute('''
      CREATE TABLE entity_relations (
        id TEXT PRIMARY KEY NOT NULL,
        from_entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
        to_entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
        relation_type TEXT NOT NULL CHECK (relation_type IN (
          'OWNS_PROPERTY', 'OWNS_STAKE', 'SPONSORED_BY',
          'PLAYS_FOR', 'IMPACTED_BY_NEWS'
        )),
        relation_detail TEXT,
        source_id TEXT REFERENCES sources(id),
        valid_from TEXT,
        valid_to TEXT,
        UNIQUE(from_entity_id, to_entity_id, relation_type, relation_detail)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_relations_from ON entity_relations(from_entity_id)',
    );
    await db.execute(
      'CREATE INDEX idx_relations_to ON entity_relations(to_entity_id)',
    );
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE entities ADD COLUMN source_id TEXT REFERENCES sources(id)',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE entity_relations ADD COLUMN source_id TEXT REFERENCES sources(id)',
      );
      await db.execute(
        'ALTER TABLE entity_relations ADD COLUMN valid_from TEXT',
      );
      await db.execute('ALTER TABLE entity_relations ADD COLUMN valid_to TEXT');
    }
  }
}
