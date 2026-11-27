import 'dart:convert';
import 'dart:io';

import 'package:path_provider_windows/path_provider_windows.dart';

import 'ticket_pesagem.dart';

enum PrinterFormat {
  ticket('Ticket/Cupom'),
  a4('A4');

  const PrinterFormat(this.label);
  final String label;

  PrinterFormat get alternative => this == ticket ? a4 : ticket;
}

enum TicketLogo { standard, demonstration }

class PrintDestination {
  bool enabled = false;
  String? queue;
  PrinterPaper? paper;
  int copies = 1;

  bool get configured => enabled && queue != null;

  void restore(Map<String, dynamic> json) {
    enabled = json['enabled'] == true;
    queue = json['queue'] as String?;
    copies = json['copies'] as int? ?? 1;
    final savedPaper = json['paper'] as Map<String, dynamic>?;
    paper = savedPaper == null ? null : PrinterPaper.fromJson(savedPaper);
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'queue': queue,
    'paper': paper?.toJson(),
    'copies': copies,
  };
}

/// Medidas em décimos de milímetro, conforme a API do driver.
class PrinterPaper {
  const PrinterPaper(this.id, this.name, this.width, this.height);
  final int id, width, height;
  final String name;

  String get label => '${width / 10} × ${height / 10} mm · $name';
  bool get isA4 => width == 2100 && height == 2970;
  bool get isRoll => width > 0 && width < 2100 && height > 0;

  bool matches(PrinterPaper other) =>
      id == other.id &&
      name == other.name &&
      width == other.width &&
      height == other.height;

  factory PrinterPaper.fromJson(Map<String, dynamic> json) => PrinterPaper(
    json['id'] as int,
    json['name'] as String,
    json['width'] as int,
    json['height'] as int,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
  };
}

class PrintSettings {
  PrintSettings({this.simulated = false});

  final ticket = PrintDestination();
  final a4 = PrintDestination();
  PrinterFormat preferred = PrinterFormat.ticket;
  TicketLogo logo = TicketLogo.standard;
  bool emitEntry = true, emitExit = true, simulated;
  String companyName = TicketBranding.defaultCompanyName;
  String header = '', footer = '';

  bool printsAutomatically({required bool closing}) =>
      closing ? emitExit : emitEntry;

  PrintDestination destination(PrinterFormat format) =>
      format == PrinterFormat.ticket ? ticket : a4;

  factory PrintSettings.fromJson(Map<String, dynamic> json) {
    final settings = PrintSettings(simulated: json['simulated'] == true);
    settings.preferred = PrinterFormat.values.byName(
      json['preferred'] as String? ?? PrinterFormat.ticket.name,
    );
    settings.logo = TicketLogo.values.byName(
      json['logo'] as String? ?? TicketLogo.standard.name,
    );
    settings.emitEntry = json['emitEntry'] != false;
    settings.emitExit = json['emitExit'] != false;
    settings.companyName =
        json['companyName'] as String? ?? TicketBranding.defaultCompanyName;
    settings.header = json['header'] as String? ?? '';
    settings.footer = json['footer'] as String? ?? '';
    for (final format in PrinterFormat.values) {
      settings
          .destination(format)
          .restore(json[format.name] as Map<String, dynamic>? ?? const {});
    }
    return settings;
  }

  Map<String, Object?> toJson() => {
    'simulated': simulated,
    'preferred': preferred.name,
    'logo': logo.name,
    'emitEntry': emitEntry,
    'emitExit': emitExit,
    'companyName': companyName,
    'header': header,
    'footer': footer,
    for (final format in PrinterFormat.values)
      format.name: destination(format).toJson(),
  };
}

class LocalPrintSettingsStore {
  LocalPrintSettingsStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _applicationDirectory;

  final Future<Directory> Function() _directory;
  Future<void> _logWrites = Future.value();

  static Future<Directory> _applicationDirectory() async {
    final path = await PathProviderWindows().getApplicationSupportPath();
    if (path == null) {
      throw const FileSystemException('Diretório local indisponível.');
    }
    return Directory(path);
  }

  Future<File> _file(String name) async {
    final root = await _directory();
    await root.create(recursive: true);
    return File('${root.path}/$name');
  }

  Future<Map<String, Map<String, dynamic>>> load() async {
    final file = await _file('print-settings.json');
    if (!await file.exists()) return {};
    final data = Map<String, Map<String, dynamic>>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
    for (final station in data.values) {
      PrintSettings.fromJson(station);
    }
    return data;
  }

  Future<void> save(Map<String, Map<String, dynamic>> stations) async {
    final file = await _file('print-settings.json');
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(stations), flush: true);
    await pending.rename(file.path);
  }

  void log(Map<String, Object?> record) {
    _logWrites = _logWrites
        .then((_) async {
          final file = await _file('print-jobs.jsonl');
          if (await file.exists() && await file.length() >= 1024 * 1024) {
            await file.rename('${file.path}.previous');
          }
          await file.writeAsString(
            '${jsonEncode(record)}\n',
            mode: FileMode.append,
          );
        })
        .catchError((Object _) {
          // Falhas de diagnóstico não alteram o resultado enviado ao operador.
        });
  }
}
