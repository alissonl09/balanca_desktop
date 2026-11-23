class DatabaseMigration {
  const DatabaseMigration(this.version, this.name, this.sql);
  final int version;
  final String name, sql;
}

const databaseMigrations = [
  DatabaseMigration(1, 'V001__infraestrutura_e_contingencia', '''
CREATE TABLE BAL_SCHEMA_VERSION (
 version INTEGER PRIMARY KEY, name TEXT NOT NULL, executed_at TEXT NOT NULL,
 result TEXT NOT NULL, hash TEXT NOT NULL);
CREATE TABLE BAL_DB_SCRIPT_HIST (
 id INTEGER PRIMARY KEY, filename TEXT NOT NULL, hash TEXT NOT NULL,
 executed_at TEXT NOT NULL, version_before INTEGER NOT NULL,
 version_after INTEGER NOT NULL, status TEXT NOT NULL, error TEXT,
 operator TEXT, origin TEXT NOT NULL);
CREATE INDEX BAL_SCRIPT_HASH ON BAL_DB_SCRIPT_HIST(hash, status);
CREATE TABLE BAL_DB_META (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE BAL_PESAGEM (
 id TEXT PRIMARY KEY, pre_ticket_id TEXT NOT NULL, plate TEXT NOT NULL,
 created_at TEXT NOT NULL, phase TEXT NOT NULL,
 first_reading REAL, second_reading REAL);
CREATE TABLE BAL_SYNC_EVENTO (
 id TEXT PRIMARY KEY, weighing_id TEXT NOT NULL REFERENCES BAL_PESAGEM(id),
 type TEXT NOT NULL, payload TEXT NOT NULL CHECK(json_valid(payload)),
 created_at TEXT NOT NULL, sequence INTEGER NOT NULL, depends_on TEXT,
 status TEXT NOT NULL, attempts INTEGER NOT NULL, last_error TEXT, remote_id TEXT,
 UNIQUE(weighing_id, sequence));
CREATE INDEX BAL_SYNC_PENDING ON BAL_SYNC_EVENTO(status, weighing_id, sequence);
'''),
];
