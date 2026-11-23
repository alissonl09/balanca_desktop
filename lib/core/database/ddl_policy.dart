import 'dart:convert';

import 'package:crypto/crypto.dart';

class SqlScriptPreview {
  SqlScriptPreview(this.filename, this.content)
    : hash = sha256.convert(utf8.encode(content)).toString() {
    try {
      statements = DdlPolicy.analyze(content);
    } on FormatException catch (e) {
      rejection = e.message;
    }
  }
  final String filename, content, hash;
  List<String> statements = const [];
  String? rejection;
  bool get allowed => rejection == null;
}

class _Token {
  const _Token(this.text, [this.quoted = false]);
  final String text;
  final bool quoted;
  String get word => quoted ? '' : text.toUpperCase();
}

/// Subconjunto deliberadamente restrito de DDL. Não é um console SQL.
/// Strings, identificadores escapados e comentários são tratados lexicalmente.
class DdlPolicy {
  static const protectedTables = {
    'BAL_SCHEMA_VERSION',
    'BAL_DB_SCRIPT_HIST',
    'BAL_DB_META',
  };
  static bool _protected(String name) =>
      name.toUpperCase().startsWith('SQLITE_') ||
      name.toUpperCase().startsWith('BAL_SCRIPT_') ||
      protectedTables.contains(name.toUpperCase());

  static List<String> analyze(String sql) {
    if (utf8.encode(sql).length > 1024 * 1024) {
      throw const FormatException('Script excede o limite de 1 MB.');
    }
    final groups = <List<_Token>>[];
    var tokens = <_Token>[];
    var i = 0;
    while (i < sql.length) {
      final c = sql[i];
      if (RegExp(r'\s').hasMatch(c)) {
        i++;
        continue;
      }
      if (sql.startsWith('--', i)) {
        final end = sql.indexOf('\n', i);
        i = end < 0 ? sql.length : end;
        continue;
      }
      if (sql.startsWith('/*', i)) {
        final end = sql.indexOf('*/', i + 2);
        if (end < 0) throw const FormatException('Comentário SQL incompleto.');
        i = end + 2;
        continue;
      }
      if (c == ';') {
        if (tokens.isNotEmpty) groups.add(tokens);
        tokens = [];
        i++;
        continue;
      }
      if (c == "'" || c == '"' || c == '`' || c == '[') {
        final start = i++;
        final endQuote = c == '[' ? ']' : c;
        var closed = false;
        while (i < sql.length) {
          if (sql[i++] == endQuote) {
            if (c != '[' && i < sql.length && sql[i] == endQuote) {
              i++;
              continue;
            }
            closed = true;
            break;
          }
        }
        if (!closed) {
          throw const FormatException('Texto ou identificador SQL incompleto.');
        }
        tokens.add(_Token(sql.substring(start, i), true));
      } else {
        final match = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*|^[0-9]+(?:\.[0-9]+)?')
            .firstMatch(sql.substring(i));
        if (match != null) {
          tokens.add(_Token(match[0]!));
          i += match[0]!.length;
        } else if ('(),+-*/%<>=!|&~'.contains(c)) {
          tokens.add(_Token(c));
          i++;
        } else {
          throw FormatException('Símbolo não permitido no script: $c');
        }
      }
    }
    if (tokens.isNotEmpty) groups.add(tokens);
    if (groups.isEmpty || groups.length > 200) {
      throw const FormatException(
        'Selecione um script com 1 a 200 comandos DDL.',
      );
    }
    return groups.map(_validate).toList();
  }

  static String _identifier(_Token token) {
    var text = token.text;
    if (token.quoted) {
      if (text.startsWith("'")) {
        throw const FormatException('Use identificadores SQL, não strings.');
      }
      text = text.substring(1, text.length - 1);
    }
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(text) ||
        _protected(text)) {
      throw const FormatException(
        'Identificador protegido ou fora do padrão permitido.',
      );
    }
    return text;
  }

  static String _validate(List<_Token> t) {
    String word(int i) => i < t.length ? t[i].word : '';
    final words = t.map((e) => e.word).toList();
    const blocked = {
      'ATTACH',
      'DETACH',
      'PRAGMA',
      'VACUUM',
      'REINDEX',
      'ANALYZE',
      'INSERT',
      'UPDATE',
      'DELETE',
      'REPLACE',
      'SELECT',
      'TRIGGER',
      'VIEW',
      'VIRTUAL',
      'BEGIN',
      'COMMIT',
      'END',
      'ROLLBACK',
      'SAVEPOINT',
      'RELEASE',
      'RENAME',
    };
    if (words.any(blocked.contains)) {
      throw const FormatException(
        'Comando bloqueado. Permitidos: CREATE TABLE, CREATE INDEX, ALTER TABLE ADD COLUMN e DROP INDEX.',
      );
    }
    var object = -1;
    if (word(0) == 'CREATE' && word(1) == 'TABLE') {
      object = word(2) == 'IF' && word(3) == 'NOT' && word(4) == 'EXISTS'
          ? 5
          : 2;
    } else if (word(0) == 'ALTER' && word(1) == 'TABLE' && word(3) == 'ADD') {
      object = 2;
      if (words.contains('DROP')) {
        throw const FormatException('DROP COLUMN bloqueado.');
      }
    } else if (word(0) == 'CREATE' &&
        (word(1) == 'INDEX' || (word(1) == 'UNIQUE' && word(2) == 'INDEX'))) {
      final start = word(1) == 'UNIQUE' ? 3 : 2;
      object =
          word(start) == 'IF' &&
              word(start + 1) == 'NOT' &&
              word(start + 2) == 'EXISTS'
          ? start + 3
          : start;
      final on = words.indexOf('ON');
      if (on < 0 || on + 1 >= t.length) {
        throw const FormatException('Índice sem tabela.');
      }
      _identifier(t[on + 1]);
    } else if (word(0) == 'DROP' && word(1) == 'INDEX') {
      object = word(2) == 'IF' && word(3) == 'EXISTS' ? 4 : 2;
      if (t.length != object + 1) {
        throw const FormatException('DROP INDEX inválido.');
      }
    }
    if (object < 0 || object >= t.length) {
      throw const FormatException(
        'Operação bloqueada ou não transacional. Apenas DDL autorizado é aceito.',
      );
    }
    _identifier(t[object]);
    if (words.skip(1).contains('DROP') || words.contains('AS')) {
      throw const FormatException(
        'Operação destrutiva ou CREATE AS bloqueada.',
      );
    }
    // Não admitir funções arbitrárias, extensões ou efeitos externos em defaults,
    // CHECKs ou índices. As exceções são tipos, sintaxe SQL e funções puras.
    const calls = {
      'CHECK',
      'IN',
      'VALUES',
      'PRIMARY',
      'UNIQUE',
      'KEY',
      'VARCHAR',
      'CHAR',
      'NVARCHAR',
      'DECIMAL',
      'NUMERIC',
      'TEXT',
      'INTEGER',
      'REAL',
      'BLOB',
      'LENGTH',
      'ABS',
      'COALESCE',
      'TYPEOF',
      'LOWER',
      'UPPER',
      'TRIM',
      'ROUND',
      'IFNULL',
    };
    for (var i = 0; i + 1 < t.length; i++) {
      if (t[i + 1].text != '(' || '(),+-*/%<>=!|&~'.contains(t[i].text)) {
        continue;
      }
      if (i == object ||
          (i > 0 && {'REFERENCES', 'ON'}.contains(word(i - 1)))) {
        continue;
      }
      if (!calls.contains(word(i))) {
        throw const FormatException(
          'Função ou expressão avançada não permitida no DDL.',
        );
      }
    }
    return t.map((e) => e.text).join(' ');
  }
}
