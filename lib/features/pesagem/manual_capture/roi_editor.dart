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
      deskewDegrees: region.deskewDegrees,
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
                child: Icon(Icons.open_in_full, size: 18, color: Colors.black),
              ),
            ),
          ),
        ],
      );
    },
  );
}
