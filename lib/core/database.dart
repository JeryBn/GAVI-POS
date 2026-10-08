import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

class PosDatabase extends GeneratedDatabase {
  PosDatabase(super.executor);
  PosDatabase.open(String name)
    : super(driftDatabase(name: name, web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      )));
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {
    for (final sql in schema) { await customStatement(sql); }
  }, beforeOpen: (_) async {
    await customStatement('PRAGMA foreign_keys = ON');
  });
  static const schema = [
    'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    '''CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL,
      sku TEXT NOT NULL UNIQUE, barcode TEXT NOT NULL, price INTEGER NOT NULL CHECK(price>=0),
      wholesale INTEGER NOT NULL CHECK(wholesale>=0), minimum INTEGER NOT NULL CHECK(minimum>=0),
      cost INTEGER NOT NULL CHECK(cost>=0), stock INTEGER NOT NULL CHECK(stock>=0),
      low INTEGER NOT NULL CHECK(low>=0), active INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE documents (id TEXT PRIMARY KEY, kind TEXT NOT NULL,
      created TEXT NOT NULL, actor TEXT NOT NULL, body TEXT NOT NULL)''',
    '''CREATE TABLE outbox (id TEXT PRIMARY KEY REFERENCES documents(id),
      state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
      error TEXT, acknowledged TEXT)''',
    'CREATE INDEX documents_kind ON documents(kind, created)',
    "CREATE UNIQUE INDEX product_barcode ON products(barcode) WHERE barcode<>''",
    'CREATE INDEX outbox_state ON outbox(state)',
  ];
}
