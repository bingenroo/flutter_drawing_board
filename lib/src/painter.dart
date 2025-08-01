import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../paint_contents.dart';
import 'drawing_controller.dart';
import 'helper/ex_value_builder.dart';
import 'paint_contents/paint_content.dart';
import 'dart:async';

/// 绘图板
class Painter extends StatelessWidget {
  final void Function(Offset?)?
      onHoldAfterDraw; // NEW: Callback for hold after draw
  Painter({
    super.key,
    required this.drawingController,
    this.clipBehavior = Clip.antiAlias,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onHoldAfterDraw, // NEW
  });

  /// 绘制控制器
  final DrawingController drawingController;

  /// 开始拖动
  final void Function(PointerDownEvent pde)? onPointerDown;

  /// 正在拖动
  final void Function(PointerMoveEvent pme)? onPointerMove;

  /// 结束拖动
  final void Function(PointerUpEvent pue)? onPointerUp;

  /// 边缘裁剪方式
  final Clip clipBehavior;

  Timer? _holdTimer; // NEW
  Offset? _lastPointerDownPosition; // NEW
  bool _snappedToStraight = false; // NEW
  static const double _snapHoldDuration = 0.5; // seconds
  static const double _snapMoveTolerance = 8.0; // px

  /// 手指落下
  void _onPointerDown(PointerDownEvent pde) {
    _holdTimer?.cancel();
    _snappedToStraight = false;
    _lastPointerDownPosition = pde.localPosition;
    if (!drawingController.couldStartDraw) {
      return;
    }
    drawingController.startDraw(pde.localPosition);
    // Start hold timer for snapping
    _holdTimer =
        Timer(Duration(milliseconds: (_snapHoldDuration * 1000).toInt()), () {
      if (!_snappedToStraight && _lastPointerDownPosition != null) {
        drawingController.snapCurrentToStraightLine(_lastPointerDownPosition!);
        _snappedToStraight = true;
      }
    });
    onPointerDown?.call(pde);
  }

  /// 手指移动
  void _onPointerMove(PointerMoveEvent pme) {
    if (!drawingController.couldDrawing) {
      if (drawingController.hasPaintingContent) {
        drawingController.endDraw();
      }
      return;
    }
    if (!drawingController.hasPaintingContent) {
      return;
    }
    // If not snapped, check movement
    if (!_snappedToStraight && _lastPointerDownPosition != null) {
      final dist = (pme.localPosition - _lastPointerDownPosition!).distance;
      if (dist > _snapMoveTolerance) {
        // Too much movement, reset timer
        _holdTimer?.cancel();
        _lastPointerDownPosition = pme.localPosition;
        _holdTimer = Timer(
            Duration(milliseconds: (_snapHoldDuration * 1000).toInt()), () {
          if (!_snappedToStraight && _lastPointerDownPosition != null) {
            drawingController
                .snapCurrentToStraightLine(_lastPointerDownPosition!);
            _snappedToStraight = true;
          }
        });
      }
    }
    // If snapped, update straight line end point
    if (_snappedToStraight) {
      if (drawingController.currentContent is StraightLine) {
        (drawingController.currentContent as StraightLine).endPoint =
            pme.localPosition;
        drawingController.notifyListeners();
      }
    } else {
      drawingController.drawing(pme.localPosition);
    }
    onPointerMove?.call(pme);
  }

  /// 手指抬起
  void _onPointerUp(PointerUpEvent pue) {
    _holdTimer?.cancel();
    _snappedToStraight = false;
    _lastPointerDownPosition = null;
    if (!drawingController.couldDrawing ||
        !drawingController.hasPaintingContent) {
      return;
    }
    if (drawingController.startPoint == pue.localPosition) {
      drawingController.drawing(pue.localPosition);
    }
    drawingController.endDraw();
    onPointerUp?.call(pue);
  }

  void _onPointerCancel(PointerCancelEvent pce) {
    _holdTimer?.cancel();
    _snappedToStraight = false;
    _lastPointerDownPosition = null;
    if (!drawingController.couldDrawing) {
      return;
    }
    drawingController.endDraw();
  }

  /// GestureDetector 占位
  void _onPanDown(DragDownDetails ddd) {}

  void _onPanUpdate(DragUpdateDetails dud) {}

  void _onPanEnd(DragEndDetails ded) {}

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      behavior: HitTestBehavior.opaque,
      child: ExValueBuilder<DrawConfig>(
        valueListenable: drawingController.drawConfig,
        shouldRebuild: (DrawConfig p, DrawConfig n) =>
            p.fingerCount != n.fingerCount,
        builder: (_, DrawConfig config, Widget? child) {
          // 是否能拖动画布
          final bool isPanEnabled = config.fingerCount > 1;

          return GestureDetector(
            onPanDown: !isPanEnabled ? _onPanDown : null,
            onPanUpdate: !isPanEnabled ? _onPanUpdate : null,
            onPanEnd: !isPanEnabled ? _onPanEnd : null,
            child: child,
          );
        },
        child: ClipRect(
          clipBehavior: clipBehavior,
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              painter: _DeepPainter(controller: drawingController),
              child: RepaintBoundary(
                child: CustomPaint(
                  isComplex: true,
                  painter: _UpPainter(controller: drawingController),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 表层画板
class _UpPainter extends CustomPainter {
  _UpPainter({required this.controller}) : super(repaint: controller.painter);

  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.hasPaintingContent) {
      return;
    }

    if (controller.eraserContent != null) {
      canvas.saveLayer(Offset.zero & size, Paint());

      if (controller.cachedImage != null) {
        canvas.drawImage(controller.cachedImage!, Offset.zero, Paint());
      }
      controller.eraserContent?.draw(canvas, size, false);

      canvas.restore();
    } else {
      controller.currentContent?.draw(canvas, size, false);
    }
  }

  @override
  bool shouldRepaint(covariant _UpPainter oldDelegate) => false;
}

/// 底层画板
class _DeepPainter extends CustomPainter {
  _DeepPainter({required this.controller})
      : super(repaint: controller.realPainter);
  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.eraserContent != null) {
      return;
    }

    final List<PaintContent> contents = <PaintContent>[
      ...controller.getHistory,
      if (controller.eraserContent != null) controller.eraserContent!,
    ];

    if (contents.isEmpty) {
      return;
    }

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas tempCanvas = Canvas(
        recorder, Rect.fromPoints(Offset.zero, size.bottomRight(Offset.zero)));

    canvas.saveLayer(Offset.zero & size, Paint());

    for (int i = 0; i < controller.currentIndex; i++) {
      contents[i].draw(canvas, size, true);
      contents[i].draw(tempCanvas, size, true);
    }

    canvas.restore();

    final ui.Picture picture = recorder.endRecording();
    picture
        .toImage(size.width.toInt(), size.height.toInt())
        .then((ui.Image value) {
      controller.cachedImage = value;
    });
  }

  @override
  bool shouldRepaint(covariant _DeepPainter oldDelegate) => false;
}
