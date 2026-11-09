import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'capture_models.dart';

/// Shares the preview's exact aspect ratio: pointer coordinates are normalized
/// before the processor maps them to the decoded camera snapshot.
class DisplayRegionEditor extends StatefulWidget {
  const DisplayRegionEditor({
    super.key,
    required this.region,
    required this.onChanged,
  });
  final DisplayRegion region;
  final ValueChanged<DisplayRegion> onChanged;
  @override
  State<DisplayRegionEditor> createState() => _DisplayRegionEditorState();
}

class _DisplayRegionEditorState extends State<DisplayRegionEditor> {
  DisplayRegion? _origin;
  Offset _total = Offset.zero;
  void _start(DragStartDetails event) {
    _origin = widget.region;
    _total = Offset.zero;
  }

  void _move(Offset delta, Size size, {bool resize = false}) {
    _total += delta;
    final region = _origin ?? widget.region;
    delta = _total;
    final next = DisplayRegion(
      calibrated: true,
      deskewDegrees: region.deskewDegrees,
      corners: region.corners,
      left: resize
          ? region.left
          : (region.left + delta.dx / size.width).clamp(0, 1 - region.width),
      top: resize
          ? region.top
          : (region.top + delta.dy / size.height).clamp(0, 1 - region.height),
      width: resize
          ? (region.width + delta.dx / size.width).clamp(.02, 1 - region.left)
          : region.width,
      height: resize
          ? (region.height + delta.dy / size.height).clamp(.02, 1 - region.top)
          : region.height,
    );
    if (next.valid) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final size = bounds.biggest;
      final region = widget.region;
      return Stack(
        children: [
          Positioned(
            left: size.width * region.left,
            top: size.height * region.top,
            width: size.width * region.width,
            height: size.height * region.height,
            child: GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              key: const ValueKey('roi-move'),
              behavior: HitTestBehavior.opaque,
              onPanStart: _start,
              onPanUpdate: (event) => _move(event.delta, size),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.amber, width: 2),
                ),
              ),
            ),
          ),
          if (region.corners.isEmpty)
            Positioned(
              left: size.width * (region.left + region.width) - 16,
              top: size.height * (region.top + region.height) - 16,
              width: 32,
              height: 32,
              child: GestureDetector(
                dragStartBehavior: DragStartBehavior.down,
                key: const ValueKey('roi-resize'),
                behavior: HitTestBehavior.opaque,
                onPanStart: _start,
                onPanUpdate: (event) => _move(event.delta, size, resize: true),
                child: const ColoredBox(
                  color: Colors.amber,
                  child: Icon(
                    Icons.open_in_full,
                    size: 18,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          if (region.corners.isNotEmpty) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _PerspectivePainter(region)),
              ),
            ),
            for (var i = 0; i < 4; i++)
              Positioned(
                left:
                    size.width *
                        (region.left + region.corners[i].x * region.width) -
                    12,
                top:
                    size.height *
                        (region.top + region.corners[i].y * region.height) -
                    12,
                width: 24,
                height: 24,
                child: GestureDetector(
                  key: ValueKey('perspective-corner-$i'),
                  onPanStart: _start,
                  onPanUpdate: (event) {
                    _total += event.delta;
                    final origin = _origin ?? region;
                    final corners = List<DisplayPoint>.of(origin.corners);
                    corners[i] = DisplayPoint(
                      (origin.corners[i].x +
                              _total.dx / (size.width * region.width))
                          .clamp(0, 1),
                      (origin.corners[i].y +
                              _total.dy / (size.height * region.height))
                          .clamp(0, 1),
                    );
                    final next = DisplayRegion(
                      calibrated: true,
                      left: region.left,
                      top: region.top,
                      width: region.width,
                      height: region.height,
                      deskewDegrees: region.deskewDegrees,
                      corners: corners,
                    );
                    if (next.valid) widget.onChanged(next);
                  },
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.cyan,
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text('${i + 1}')),
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _PerspectivePainter extends CustomPainter {
  const _PerspectivePainter(this.region);
  final DisplayRegion region;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final p = region.corners[i];
      final x = (region.left + p.x * region.width) * size.width,
          y = (region.top + p.y * region.height) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PerspectivePainter oldDelegate) =>
      oldDelegate.region != region;
}
