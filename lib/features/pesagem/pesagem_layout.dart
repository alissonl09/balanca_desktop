import 'package:flutter/widgets.dart';

enum DesktopDensity { amplo, medio, compacto }

/// Medidas lógicas da área de conteúdo, após cabeçalho, menu e margens.
/// As fontes não são escaladas; apenas espaçamentos e alturas mudam de faixa.
class PesagemLayout {
  PesagemLayout.fromSize(Size size, {this.localNotice = false})
    : availableHeight = size.height,
      density = size.width >= 1440 && size.height >= 900
          ? DesktopDensity.amplo
          : size.width >= 1260 && size.height >= 750
          ? DesktopDensity.medio
          : DesktopDensity.compacto;

  final DesktopDensity density;
  final double availableHeight;
  final bool localNotice;
  bool get tightHeight => availableHeight < 620;
  bool get compact => density == DesktopDensity.compacto;
  bool get spacious => density == DesktopDensity.amplo;
  double get cardPadding => spacious
      ? 18
      : compact
      ? 4
      : 14;
  double get sectionPadding => spacious
      ? 14
      : compact
      ? 8
      : 10;
  double get gap => spacious
      ? 14
      : compact
      ? 4
      : 10;
  double get fieldGap => spacious
      ? 10
      : compact
      ? 4
      : 8;
  double get fieldHeight => spacious
      ? 40
      : compact
      ? 34
      : 36;
  double get operationFieldHeight => fieldHeight;
  double get operationRowGap => tightHeight
      ? fieldGap
      : spacious
      ? 12
      : compact
      ? 8
      : 10;
  double get operationPadding => tightHeight
      ? sectionPadding
      : spacious
      ? 16
      : compact
      ? 11
      : 12;
  double get operationHeadingGap =>
      tightHeight ? (compact ? 6 : 10) : (compact ? 9 : 12);
  double get labelGap => compact ? 3 : 4;
  double get displayHeight => spacious
      ? 122
      : compact
      ? 88
      : 100;
  double get panelPadding => spacious
      ? 12
      : compact
      ? 8
      : 10;
  double get panelHeadingHeight => spacious ? 28 : 24;
  double get sideWidth => spacious
      ? 315
      : compact
      ? 286
      : 300;
  double get actionHeight => spacious
      ? 54
      : compact
      ? 44
      : 48;
  double get queueRowHeight => spacious
      ? 39
      : compact
      ? 30
      : 34;
}
