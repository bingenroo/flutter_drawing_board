import 'dart:math';
import 'package:flutter/material.dart';

/// A grid-based spatial index for fast hit-testing of strokes.
/// Used for efficient eraser and selection operations.
class SpatialIndex {
  SpatialIndex(this.cellSize);
  final double cellSize;
  final Map<Point<int>, List<int>> grid = <Point<int>, List<int>>{};

  /// Adds a stroke to the spatial index, mapping its bounding box to grid cells.
  void addStroke(int strokeId, Rect bounds) {
    final Point<int> startCell = _pointToCell(bounds.topLeft);
    final Point<int> endCell = _pointToCell(bounds.bottomRight);

    for (int x = startCell.x; x <= endCell.x; x++) {
      for (int y = startCell.y; y <= endCell.y; y++) {
        final Point<int> cell = Point<int>(x, y);
        grid.putIfAbsent(cell, () => <int>[]).add(strokeId);
      }
    }
  }

  /// Converts a point to its corresponding grid cell.
  Point<int> _pointToCell(Offset point) {
    return Point((point.dx / cellSize).floor(), (point.dy / cellSize).floor());
  }

  /// Returns candidate stroke IDs that may intersect a circle at [point] with [radius].
  List<int> getCandidates(Offset point, double radius) {
    final Set<int> candidates = <int>{};
    final Point<int> topLeft = _pointToCell(Offset(point.dx - radius, point.dy - radius));
    final Point<int> bottomRight = _pointToCell(Offset(point.dx + radius, point.dy + radius));

    for (int x = topLeft.x; x <= bottomRight.x; x++) {
      for (int y = topLeft.y; y <= bottomRight.y; y++) {
        final Point<int> cell = Point<int>(x, y);
        final List<int>? cellCandidates = grid[cell];
        cellCandidates?.forEach((int candidate) {
          candidates.add(candidate);
        });
      }
    }
    return candidates.toList();
  }

  /// Clears the spatial index.
  void clear() {
    grid.clear();
  }
}
