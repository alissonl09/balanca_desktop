import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/database/ddl_policy.dart';

void main() {
  for (final sql in [
    'DROP TABLE BAL_PESAGEM;',
    'ALTER TABLE BAL_PESAGEM DROP COLUMN plate;',
    'DELETE FROM BAL_PESAGEM;',
    'UPDATE BAL_PESAGEM SET plate=\'a\';',
    'INSERT INTO x VALUES(1);',
    "ATTACH DATABASE 'x' AS other;",
    'DETACH DATABASE x;',
    'PRAGMA writable_schema=ON;',
    "VACUUM INTO 'external.db';",
    'BEGIN; CREATE TABLE x(id); COMMIT;',
    'CREATE VIRTUAL TABLE x USING fts5(value);',
    'CREATE VIEW x AS SELECT 1;',
    'ALTER TABLE BAL_DB_SCRIPT_HIST ADD COLUMN x;',
    'DROP INDEX BAL_SCRIPT_HASH;',
    'CREATE INDEX x ON BAL_DB_META(value);',
    "CREATE TABLE x(id DEFAULT (load_extension('outside')));",
    "CREATE TABLE x(id DEFAULT (writefile('outside','a')));",
    "CREATE TABLE x(id DEFAULT (\"load_extension\"('outside')));",
    'CREATE TABLE main.x(id);',
    '/* incomplete',
    "CREATE TABLE x(id TEXT DEFAULT 'incomplete);",
  ]) {
    test('bloqueia $sql', () {
      expect(SqlScriptPreview('test.sql', sql).allowed, isFalse);
    });
  }
  test('strings e comentários não confundem comandos nem separador', () {
    final preview = SqlScriptPreview(
      'test.sql',
      "-- DELETE deve ficar só em comentário\n"
          "CREATE TABLE sample(id INTEGER PRIMARY KEY, value TEXT DEFAULT 'a; DROP TABLE y;');"
          '/* ATTACH */ CREATE INDEX sample_value ON sample(value);',
    );
    expect(preview.allowed, isTrue);
    expect(preview.statements.length, 2);
    expect(preview.statements.first, contains("'a; DROP TABLE y;'"));
  });
  test('limites do script e conjunto vazio', () {
    expect(SqlScriptPreview('empty.sql', '-- empty').allowed, isFalse);
    expect(
      SqlScriptPreview('large.sql', 'x' * (1024 * 1024 + 1)).allowed,
      isFalse,
    );
    expect(
      SqlScriptPreview('many.sql', 'CREATE TABLE x(id);' * 201).allowed,
      isFalse,
    );
  });
}
