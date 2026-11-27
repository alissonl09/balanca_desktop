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
  bool get tightHeight => availableHeight < 660;
  bool get shortHeight => availableHeight < 610;
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
      : 8;
  double get verticalGap => shortHeight ? 2 : gap;
  double get fieldHeight => spacious ? 40 : (compact ? 36 : 38);
  double get operationRowGap => spacious ? 10 : 8;
  double get operationVerticalPadding => spacious ? 12 : (tightHeight ? 6 : 8);
  double get operationHeadingGap => spacious ? 8 : 6;
  double get labelGap => 4;
  double get displayHeight => spacious
      ? 122
      : compact
      ? (shortHeight ? 78 : 88)
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
      ? (shortHeight ? 268 : 286)
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
