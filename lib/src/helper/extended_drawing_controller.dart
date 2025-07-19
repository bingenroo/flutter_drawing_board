import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../drawing_controller.dart';
import '../paint_contents/paint_content.dart';
import 'spatial_index.dart';

/// Extended controller for advanced eraser and spatial indexing features.
class ExtendedDrawingController {
  ExtendedDrawingController(this._drawingController);
  final DrawingController _drawingController;
  final SpatialIndex _spatialIndex = SpatialIndex(50); // 50px grid
  List<Map<String, dynamic>> _strokes = <Map<String, dynamic>>[];

  void addNewStroke(Map<String, dynamic> stroke) {
    _strokes.add(stroke);
    final Rect bounds = _calculateBounds(stroke);
    _spatialIndex.addStroke(_strokes.length - 1, bounds);
  }

  // Call this when the drawing changes
  void updateFromController() {
    initialize(_drawingController.getJsonList());
  }

  void initialize(List<Map<String, dynamic>> strokes) {
    _spatialIndex.clear();
    _strokes = strokes;
    for (int i = 0; i < strokes.length; i++) {
      final Rect bounds = _calculateBounds(strokes[i]);
      _spatialIndex.addStroke(i, bounds);
    }
  }

  void trackNewStrokes(List<Map<String, dynamic>> currentStrokes) {
    final List<int> newIndices = <int>[];
    for (int i = _strokes.length; i < currentStrokes.length; i++) {
      newIndices.add(i);
    }
    for (final int index in newIndices) {
      final Map<String, dynamic> stroke = currentStrokes[index];
      _strokes.add(stroke);
      final Rect bounds = _calculateBounds(stroke);
      _spatialIndex.addStroke(index, bounds);
    }
  }

  /// Process eraser points and remove matching drawing data
  /// Returns the updated drawing data after erasing
  List<Map<String, dynamic>> processEraserPoints(
    List<String> newPoints, {
    double eraserRadius = 16.0,
  }) {
    try {
      final List<Map<String, dynamic>> currentDrawingData = _drawingController.getJsonList();
      if (currentDrawingData.isEmpty) return <Map<String, dynamic>>[];
      final List<Offset> eraserPoints = _parsePoints(newPoints);
      // Find matching strokes using spatial index
      final List<int> indicesToRemove = _findMatchingStrokes(eraserPoints, eraserRadius);
      if (indicesToRemove.isNotEmpty) {
        _removeStrokesByIndices(indicesToRemove);
        initialize(_drawingController.getJsonList()); // Rebuild index
        return _drawingController.getJsonList();
      } else {
        return currentDrawingData;
      }
    } catch (e) {
      return _drawingController.getJsonList();
    }
  }

  List<Offset> _parsePoints(List<String> pointStrings) {
    final List<Offset> points = <Offset>[];
    for (final String pointStr in pointStrings) {
      try {
        final String cleanStr = pointStr.replaceAll('(', '').replaceAll(')', '');
        final List<String> parts = cleanStr.split(',');
        if (parts.length == 2) {
          final double x = double.parse(parts[0].trim());
          final double y = double.parse(parts[1].trim());
          points.add(Offset(x, y));
        }
      } catch (_) {}
    }
    return points;
  }

  List<int> _findMatchingStrokes(List<Offset> eraserPath, double eraserRadius) {
    final Set<int> candidates = <int>{};
    for (final Offset point in eraserPath) {
      candidates.addAll(_spatialIndex.getCandidates(point, eraserRadius));
    }
    return candidates
        .where((int i) => _strokeIntersectsEraser(_strokes[i], eraserPath, eraserRadius))
        .toList();
  }

  bool _strokeIntersectsEraser(
    Map<String, dynamic> stroke,
    List<Offset> eraserPath,
    double eraserRadius,
  ) {
    switch (stroke['type']) {
      case 'StraightLine':
        final Offset start = _parseOffset(stroke['startPoint'] as Map<String, dynamic>?);
        final Offset end = _parseOffset(stroke['endPoint'] as Map<String, dynamic>?);
        return _lineIntersects(start, end, eraserPath, eraserRadius);
      case 'SimpleLine':
        final dynamic path = stroke['path'];
        if (path is Map<String, dynamic>) {
          final dynamic steps = path['steps'];
          if (steps != null && steps is List) {
            for (int i = 1; i < steps.length; i++) {
              final Offset p1 = _parseOffsetFromStep(steps[i - 1] as Map<String, dynamic>?);
              final Offset p2 = _parseOffsetFromStep(steps[i] as Map<String, dynamic>?);
              if (_lineIntersects(p1, p2, eraserPath, eraserRadius)) {
                return true;
              }
            }
          }
        }
        return false;
      case 'Rectangle':
        final Offset start = _parseOffset(stroke['startPoint'] as Map<String, dynamic>?);
        final Offset end = _parseOffset(stroke['endPoint'] as Map<String, dynamic>?);
        final List<Offset> corners = <Offset>[
          start,
          Offset(end.dx, start.dy),
          end,
          Offset(start.dx, end.dy),
        ];
        for (int i = 0; i < 4; i++) {
          if (_lineIntersects(corners[i], corners[(i + 1) % 4], eraserPath, eraserRadius)) {
            return true;
          }
        }
        return false;
      case 'Circle':
        final Offset center = _parseOffset(stroke['center'] as Map<String, dynamic>?);
        final dynamic r = stroke['radius'] ?? 0;
        final double radiusValue = (r is num) ? r.toDouble() : 0.0;
        for (final Offset e in eraserPath) {
          if ((center - e).distance <= radiusValue + eraserRadius) {
            return true;
          }
        }
        return false;
      default:
        return false;
    }
  }

  bool _lineIntersects(Offset p1, Offset p2, List<Offset> eraserPath, double radius) {
    for (final Offset center in eraserPath) {
      if (_circleIntersectsLine(center, radius, p1, p2)) {
        return true;
      }
    }
    return false;
  }

  bool _circleIntersectsLine(Offset center, double radius, Offset p1, Offset p2) {
    final Offset lineVec = p2 - p1;
    final Offset toCenter = center - p1;
    final double lineLength = lineVec.distance;
    if (lineLength == 0) {
      return (center - p1).distance <= radius;
    }
    final Offset norm = lineVec / lineLength;
    final double proj = toCenter.dx * norm.dx + toCenter.dy * norm.dy;
    final double closest = proj.clamp(0, lineLength);
    final Offset closestPoint = p1 + norm * closest;
    return (center - closestPoint).distance <= radius;
  }

  Offset _parseOffset(Map<String, dynamic>? map) {
    if (map == null) return Offset.zero;
    final dynamic dx = map['dx'] ?? 0.0;
    final dynamic dy = map['dy'] ?? 0.0;
    return Offset((dx as num).toDouble(), (dy as num).toDouble());
  }

  Offset _parseOffsetFromStep(Map<String, dynamic>? step) {
    if (step == null) return Offset.zero;
    final dynamic x = step['x'] ?? 0.0;
    final dynamic y = step['y'] ?? 0.0;
    return Offset((x as num).toDouble(), (y as num).toDouble());
  }

  Rect _calculateBounds(Map<String, dynamic> stroke) {
    switch (stroke['type']) {
      case 'StraightLine':
        final Offset start = _parseOffset(stroke['startPoint'] as Map<String, dynamic>?);
        final Offset end = _parseOffset(stroke['endPoint'] as Map<String, dynamic>?);
        return Rect.fromPoints(start, end);
      case 'SimpleLine':
        final dynamic path = stroke['path'];
        if (path is Map<String, dynamic>) {
          final dynamic steps = path['steps'];
          if (steps != null && steps is List && steps.isNotEmpty) {
            double minX = double.infinity,
                minY = double.infinity,
                maxX = -double.infinity,
                maxY = -double.infinity;
            for (final dynamic step in steps) {
              final Offset o = _parseOffsetFromStep(step as Map<String, dynamic>?);
              minX = math.min(minX, o.dx);
              minY = math.min(minY, o.dy);
              maxX = math.max(maxX, o.dx);
              maxY = math.max(maxY, o.dy);
            }
            return Rect.fromLTRB(minX, minY, maxX, maxY);
          }
        }
        return Rect.zero;
      case 'Rectangle':
        final Offset start = _parseOffset(stroke['startPoint'] as Map<String, dynamic>?);
        final Offset end = _parseOffset(stroke['endPoint'] as Map<String, dynamic>?);
        return Rect.fromPoints(start, end);
      case 'Circle':
        final Offset center = _parseOffset(stroke['center'] as Map<String, dynamic>?);
        final dynamic r = stroke['radius'] ?? 0;
        final double radiusValue = (r is num) ? r.toDouble() : 0.0;
        return Rect.fromCircle(center: center, radius: radiusValue);
      default:
        return Rect.zero;
    }
  }

  void _removeStrokesByIndices(List<int> indicesToRemove) {
    indicesToRemove.sort((int a, int b) => b.compareTo(a));
    final List<PaintContent> history = List<PaintContent>.from(_drawingController.getHistory);

    for (final int index in indicesToRemove) {
      if (index < history.length) {
        history.removeAt(index);
      }
    }

    _drawingController.clear();
    if (history.isNotEmpty) {
      _drawingController.addContents(history);
    }

    // Rebuild spatial index with current data
    initialize(_drawingController.getJsonList());
  }
}
