import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';
import 'print_settings.dart';
import 'ticket_paper.dart';
import 'ticket_pesagem.dart';
import 'ticket_sections.dart';

class PrintDocument {
  const PrintDocument._(
    this.title, {
    this.ticket,
    this.lines = const [],
    this.logo,
  });

  final String title;
  final TicketPesagem? ticket;
  final List<String> lines;
  final TicketLogoKind? logo;

  factory PrintDocument.ticket(TicketPesagem ticket) =>
      PrintDocument._('Ticket de pesagem', ticket: ticket);

  factory PrintDocument.fromJson(Map<String, dynamic> json) => PrintDocument._(
    json['title'] as String,
    ticket: json['ticket'] == null
        ? null
        : TicketPesagem.fromJson(json['ticket'] as Map<String, dynamic>),
    lines: List<String>.from(json['lines'] as List),
    logo: json['logo'] == null
        ? null
        : TicketLogoKind.values.byName(json['logo'] as String),
  );

  Map<String, Object?> toJson() => {
    'title': title,
    'ticket': ticket?.toJson(),
    'lines': lines,
    'logo': logo?.name,
  };

  factory PrintDocument.test({
    required String station,
    required String queue,
    required String paper,
    required DateTime time,
    required TicketLogoKind logo,
  }) => PrintDocument._(
    'Teste de impressão',
    logo: logo,
    lines: [
      '${ticketDate(time)} ${ticketTime(time)}',
      'Estação: $station',
      'Fila: $queue',
      'Papel: $paper',
      'Acentuação: ação, café, órgão, saída, Cooxupé.',
      'Peso de exemplo: ${ticketWeight(123456.789)}',
      'Início da linha 0123456789 / fim da linha.',
    ],
  );
}

class PrintableArea {
  const PrintableArea(this.widthMm, this.heightMm, this.dpi);
  final double widthMm, heightMm;
  final int dpi;

  bool fits(PrintableArea other) =>
      (widthMm - other.widthMm).abs() < 0.15 &&
      (heightMm - other.heightMm).abs() < 0.15;
}

class PrintPage {
  const PrintPage(this.width, this.height, this.dpi, this.pixels);
  final int width, height, dpi;
  final Uint8List pixels;
}

/// Rasteriza o papel da prévia fora da árvore da janela de pesagem.
Future<List<PrintPage>> renderPrintDocument(
  PrintDocument document,
  PrintableArea area, {
  required bool a4,
}) async {
  final dpi = area.dpi.clamp(150, 300);
  final width = (area.widthMm * dpi / 25.4).floor();
  // Limita cada imagem mesmo quando o driver anuncia metros de papel.
  final maxHeight = math.min((area.heightMm * dpi / 25.4).floor(), 4096);
  if (width <= 0 || maxHeight <= 0) {
    throw const FormatException('Área de impressão insuficiente.');
  }

  final format = a4 ? PrinterFormat.a4 : PrinterFormat.ticket;
  final paperWidth = TicketPaper.widthFor(format);
  final pixelRatio = (width - 1e-7) / paperWidth;
  final logoKind = document.ticket?.branding.logo ?? document.logo;
  final logoPicture = logoKind == TicketLogoKind.standard
      ? await vg.loadPicture(
          const SvgAssetLoader('assets/images/logo-topo.svg'),
          null,
        )
      : null;

  final boundary = _PaperBoundary();
  final constraints = BoxConstraints.tightFor(width: paperWidth);
  final view = RenderView(
    view: ui.PlatformDispatcher.instance.implicitView!,
    configuration: ViewConfiguration(
      logicalConstraints: constraints,
      physicalConstraints: constraints,
    ),
    child: boundary,
  );
  final pipeline = PipelineOwner()..rootNode = view;
  final focus = FocusManager();
  final build = BuildOwner(focusManager: focus);
  RenderObjectToWidgetElement<RenderBox>? root;

  try {
    final artwork = logoPicture == null
        ? null
        : CustomPaint(
            painter: _TicketLogoPainter(logoPicture.picture, logoPicture.size),
          );
    final ticket = document.ticket;
    final paper = ticket == null
        ? _TestPaper(document: document, standardLogo: artwork)
        : TicketPaper(
            ticket: ticket,
            format: format,
            fillSheet: false,
            standardLogo: artwork,
          );

    view.prepareInitialFrame();
    root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(data: buildAppTheme(), child: paper),
      ),
    ).attachToRenderTree(build);
    build.buildScope(root);
    build.finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    final totalHeight = (boundary.size.height * pixelRatio).ceil();
    final protected = _protectedRows(boundary, pixelRatio, maxHeight);
    final pages = <PrintPage>[];
    var start = 0;
    while (start < totalHeight) {
      var end = math.min(start + maxHeight, totalHeight);
      if (end < totalHeight) {
        for (final (top, bottom) in protected.reversed) {
          if (top < end && end < bottom) end = top;
        }
      }
      if (end <= start) {
        throw const FormatException(
          'Área de impressão insuficiente para o layout.',
        );
      }
      final image = await boundary.capture(
        Rect.fromLTWH(
          0,
          start / pixelRatio,
          paperWidth,
          (end - start - 1e-7) / pixelRatio,
        ),
        pixelRatio: pixelRatio,
      );
      try {
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        pages.add(
          PrintPage(
            image.width,
            image.height,
            dpi,
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
        );
      } finally {
        image.dispose();
      }
      start = end;
    }
    return pages;
  } finally {
    if (root != null) {
      RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
          .attachToRenderTree(build, root);
      build.buildScope(root);
      build.finalizeTree();
    }
    view.child = null;
    pipeline.rootNode = null;
    boundary.dispose();
    view.dispose();
    pipeline.dispose();
    focus.dispose();
    logoPicture?.picture.dispose();
  }
}

class _PaperBoundary extends RenderRepaintBoundary {
  Future<ui.Image> capture(Rect bounds, {required double pixelRatio}) =>
      (layer! as OffsetLayer).toImage(bounds, pixelRatio: pixelRatio);
}

/// Mantém intactos texto, linhas da tabela, logomarca e código de barras.
List<(int, int)> _protectedRows(
  RenderRepaintBoundary boundary,
  double scale,
  int maxHeight,
) {
  final rows = <(int, int)>[];

  void visit(RenderObject object) {
    if (object is RenderBox) {
      final origin = object.localToGlobal(Offset.zero, ancestor: boundary).dy;
      void protect(double top, double bottom) {
        rows.add((
          ((origin + top) * scale).floor(),
          ((origin + bottom) * scale).ceil(),
        ));
      }

      if (object is RenderParagraph) {
        for (final box in object.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: object.text.toPlainText().length,
          ),
        )) {
          protect(box.top, box.bottom);
        }
      } else if (object is RenderTable) {
        for (var row = 0; row < object.rows; row++) {
          final box = object.getRowBox(row);
          final top = ((origin + box.top) * scale).round();
          final bottom = ((origin + box.bottom) * scale).round();
          if (bottom - top <= maxHeight) rows.add((top, bottom));
        }
      } else if (object is RenderCustomPaint) {
        protect(0, object.size.height);
      } else if (object is RenderDecoratedBox &&
          object.decoration is BoxDecoration &&
          (object.decoration as BoxDecoration).border != null &&
          (object.size.height * scale).ceil() + 1 <= maxHeight) {
        protect(0, object.size.height);
      }
    }
    object.visitChildren(visit);
  }

  boundary.visitChildren(visit);
  return rows..sort((a, b) => a.$1.compareTo(b.$1));
}

class _TicketLogoPainter extends CustomPainter {
  const _TicketLogoPainter(this.picture, this.source);
  final ui.Picture picture;
  final Size source;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / source.width,
      size.height / source.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - source.width * scale) / 2,
      (size.height - source.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.saveLayer(
      Offset.zero & source,
      Paint()
        ..colorFilter = const ColorFilter.mode(Colors.black, BlendMode.srcIn),
    );
    canvas.drawPicture(picture);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TicketLogoPainter oldDelegate) =>
      oldDelegate.picture != picture;
}

class _TestPaper extends StatelessWidget {
  const _TestPaper({required this.document, this.standardLogo});
  final PrintDocument document;
  final Widget? standardLogo;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.all(20),
    child: DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'Arial',
        fontSize: 13,
        height: 1.3,
        color: Colors.black,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (document.logo case final logo?)
            TicketPaperLogo(kind: logo, size: 50, standardLogo: standardLogo),
          const Text(
            'TESTE DE IMPRESSÃO',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Divider(color: Colors.black),
          for (final line in document.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(line),
            ),
        ],
      ),
    ),
  );
}
