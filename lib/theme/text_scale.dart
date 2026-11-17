import 'package:flutter/widgets.dart';

/// Ma'am: bigger, easier to read text on every screen and every phone.
///
/// 1. Small text grows more, big text only a little:
///      11 -> 13, 13 -> 14.5, 14 -> 16, 15 -> 16.5, 16 -> 17, 20 -> 21, 24 -> 25
/// 2. Then a small step for the screen width: small phones (iPhone SE) a bit
///    smaller, big phones (Pro Max) a bit bigger, tablets capped.
/// The phone's own font size setting is not used, so layouts stay the same.
class PulseTextScaler extends TextScaler {
  const PulseTextScaler(this.widthFactor);

  /// 390 wide (a normal iPhone) = 1.0.
  factory PulseTextScaler.forWidth(double width) =>
      PulseTextScaler((width / 390).clamp(0.96, 1.06));

  final double widthFactor;

  /// Size now -> new size (straight lines in between).
  static const List<List<double>> _points = [
    [9, 10],
    [11, 12],
    [12, 13],
    [13, 14],
    [14, 15.5],
    [15, 16],
    [16, 16.5],
    [18, 18.5],
    [20, 20.5],
    [24, 24.5],
    [30, 30.5],
  ];

  static double _base(double size) {
    final first = _points.first;
    if (size <= first[0]) return size * first[1] / first[0];
    for (var i = 1; i < _points.length; i++) {
      final p = _points[i - 1];
      final q = _points[i];
      if (size <= q[0]) {
        final t = (size - p[0]) / (q[0] - p[0]);
        return p[1] + t * (q[1] - p[1]);
      }
    }
    return size + 0.5;
  }

  @override
  double scale(double fontSize) {
    // Big titles follow the screen width only half as much.
    final w = fontSize >= 24 ? 1 + (widthFactor - 1) / 2 : widthFactor;
    return _base(fontSize) * w;
  }

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => widthFactor;

  @override
  bool operator ==(Object other) =>
      other is PulseTextScaler && other.widthFactor == widthFactor;

  @override
  int get hashCode => widthFactor.hashCode;
}
