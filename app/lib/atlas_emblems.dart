import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws the six domain emblems in a 32-unit space, including their moving parts.
bool paintAtlasEmblem(
  Canvas canvas,
  Offset center,
  String domain,
  Color color,
  double clock,
) {
  final duration = switch (domain) {
    'Computing' => 320,
    'Engineering' => 400,
    'Humanities' => 420,
    'Mathematics' => 360,
    'Natural Science' => 440,
    'Social Science' => 380,
    _ => 0,
  };
  if (duration == 0) return false;
  final t = math.min(1.0, clock * 440 / duration);
  final ink = Paint()
    ..color = Color.alphaBlend(Colors.black.withValues(alpha: .22), color)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 2.25;
  canvas.save();
  canvas.translate(center.dx - 12, center.dy - 12);
  canvas.scale(.75);
  switch (domain) {
    case 'Computing':
      _terminal(canvas, ink, t);
    case 'Engineering':
      _wrench(canvas, ink, t);
    case 'Humanities':
      _book(canvas, ink, t);
    case 'Mathematics':
      _plot(canvas, ink, t);
    case 'Natural Science':
      _flask(canvas, ink, t);
    case 'Social Science':
      _chat(canvas, ink, t);
  }
  canvas.restore();
  return true;
}

void _trace(Canvas c, Path path, Paint ink, double progress) {
  if (progress >= 1) {
    c.drawPath(path, ink);
    return;
  }
  final metrics = path.computeMetrics().toList();
  var left = metrics.fold(0.0, (sum, metric) => sum + metric.length) * progress;
  for (final metric in metrics) {
    if (left <= 0) break;
    c.drawPath(metric.extractPath(0, math.min(left, metric.length)), ink);
    left -= metric.length;
  }
}

void _terminal(Canvas c, Paint ink, double t) {
  final skew = 3 * (1 - Curves.easeOut.transform(t));
  c.drawPath(
    Path()
      ..moveTo(4, 5 + skew)
      ..lineTo(28, 6)
      ..lineTo(28 - skew, 25)
      ..lineTo(4, 26 - skew)
      ..close()
      ..moveTo(4, 11 + skew)
      ..lineTo(28 - skew / 3, 11),
    ink,
  );
  _trace(
    c,
    Path()
      ..moveTo(8, 15)
      ..lineTo(13, 18.5)
      ..lineTo(8, 22),
    ink,
    const Interval(.2, .72).transform(t),
  );
  final cursor = const Interval(.47, 1, curve: Curves.easeOutBack).transform(t);
  c.drawLine(const Offset(17, 22), Offset(17 + cursor * 6, 22), ink);
}

void _wrench(Canvas c, Paint ink, double t) {
  final swing = math.sin(math.pi * t);
  final bend = 3 * math.sin(2 * math.pi * t) * (1 - t);
  c.save();
  c.translate(22, 10);
  c.rotate(-.83 * (1 - t) + .22 * swing);
  c.translate(-22, -10);
  c.drawPath(
    Path()
      ..moveTo(24.8, 4.8)
      ..cubicTo(19.3, 3, 14, 7, 16, 13.8)
      ..quadraticBezierTo(10 + bend, 18, 5 + bend, 25)
      ..quadraticBezierTo(4, 28, 8, 28.3)
      ..quadraticBezierTo(14 + bend, 22, 20, 17.5)
      ..cubicTo(25, 19, 29.5, 13, 28, 8.8)
      ..lineTo(24, 12.8)
      ..lineTo(20.1, 8.8)
      ..close(),
    ink,
  );
  c.restore();
  final impact = math.sin(math.pi * const Interval(.34, 1).transform(t));
  if (impact > 0) {
    final ticks = Paint()
      ..color = ink.color.withValues(alpha: impact)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.7;
    c.drawLine(
      const Offset(8, 11),
      Offset(8 - 4 * impact, 11 - 4 * impact),
      ticks,
    );
    c.drawLine(const Offset(12, 8), Offset(12 - impact, 8 - 4 * impact), ticks);
  }
}

void _book(Canvas c, Paint ink, double t) {
  c.drawPath(
    Path()
      ..moveTo(16, 8)
      ..quadraticBezierTo(10, 3, 4, 6)
      ..lineTo(4, 24)
      ..quadraticBezierTo(10, 22, 16, 27)
      ..quadraticBezierTo(23, 22, 28, 24)
      ..lineTo(28, 6)
      ..quadraticBezierTo(22, 3, 16, 8)
      ..lineTo(16, 27),
    ink,
  );
  c.drawPath(
    Path()
      ..moveTo(7, 12)
      ..quadraticBezierTo(10, 11, 13, 13)
      ..moveTo(7, 17)
      ..quadraticBezierTo(10, 16, 13, 18)
      ..moveTo(19, 13)
      ..quadraticBezierTo(22, 11, 25, 12)
      ..moveTo(19, 18)
      ..quadraticBezierTo(22, 16, 25, 17),
    ink,
  );
  if (t == 1) return;
  final turn = math.cos(math.pi * t);
  final arch = 6 * math.sin(math.pi * t);
  final leaf = Path()
    ..moveTo(16, 8)
    ..quadraticBezierTo(16 + 6 * turn, 2 - arch, 16 + 12 * turn, 5 - arch)
    ..lineTo(16 + 12 * turn, 23 - arch)
    ..quadraticBezierTo(16 + 5 * turn, 22 - arch, 16, 27)
    ..close();
  c.drawPath(leaf, Paint()..color = const Color(0xFFFFFBF0));
  c.drawPath(leaf, ink);
  c.drawPath(
    Path()
      ..moveTo(16 + 3 * turn, 15)
      ..quadraticBezierTo(16 + 6 * turn, 11 - arch, 16 + 9 * turn, 12 - arch),
    ink,
  );
}

void _plot(Canvas c, Paint ink, double t) {
  _trace(
    c,
    Path()
      ..moveTo(7, 4)
      ..lineTo(7, 27)
      ..lineTo(28, 27)
      ..moveTo(4.5, 7.4)
      ..lineTo(7, 4)
      ..lineTo(9.4, 7.4)
      ..moveTo(25, 24.5)
      ..lineTo(28, 27)
      ..lineTo(25, 29.4),
    ink,
    const Interval(0, .62).transform(t),
  );
  final overshoot = math.sin(2 * math.pi * t) * 5 * (1 - t);
  _trace(
    c,
    Path()
      ..moveTo(10, 22)
      ..cubicTo(14, 19, 13, 13 + overshoot, 17, 13 + overshoot)
      ..cubicTo(21, 13 + overshoot, 21, 24, 28, 8),
    ink,
    const Interval(.22, 1, curve: Curves.easeOut).transform(t),
  );
}

void _flask(Canvas c, Paint ink, double t) {
  c.drawPath(
    Path()
      ..moveTo(11.5, 4)
      ..lineTo(20.5, 4)
      ..moveTo(13.5, 4)
      ..lineTo(13.5, 13)
      ..lineTo(6.5, 24)
      ..quadraticBezierTo(5, 28, 9, 28)
      ..lineTo(24, 28)
      ..quadraticBezierTo(27, 28, 25.5, 24)
      ..lineTo(18.7, 13)
      ..lineTo(18.7, 4),
    ink,
  );
  final slosh = math.sin(3 * math.pi * t) * 4 * (1 - t);
  c.drawPath(
    Path()
      ..moveTo(10, 20 + slosh * .6)
      ..cubicTo(13, 18 - slosh, 17, 23 + slosh, 22.5, 20 - slosh * .5),
    ink,
  );
  for (var i = 0; i < 2; i++) {
    final rise = ((t - i * .14) / .86).clamp(0.0, 1.0).toDouble();
    final oval = math.sin(math.pi * rise);
    final radius = (1.13 + .55 * oval) * (1 - rise);
    if (radius > .05) {
      c.drawOval(
        Rect.fromCenter(
          center: Offset(14 + i * 4.0, 25 - (8 + i) * rise),
          width: radius * 2,
          height: radius * (2 + oval),
        ),
        ink,
      );
    }
  }
  if (t > .84) {
    c.drawCircle(const Offset(14, 24), .67, ink);
    c.drawCircle(const Offset(19, 25), .67, ink);
  }
}

void _chat(Canvas c, Paint ink, double t) {
  final press = math.sin(2 * math.pi * t) * 2.6 * (1 - t);
  final first =
      .45 +
      .55 * const Interval(0, .64, curve: Curves.easeOutBack).transform(t);
  final second =
      .42 +
      .58 * const Interval(.24, 1, curve: Curves.easeOutBack).transform(t);
  c.save();
  c.translate(8, 28);
  c.scale(second, second);
  c.translate(-8, -28);
  c.drawPath(
    Path()
      ..moveTo(7, 13)
      ..cubicTo(1, 15, 1, 23, 8, 24)
      ..lineTo(8, 28)
      ..lineTo(13, 24)
      ..quadraticBezierTo(19, 24, 21 - press, 20),
    ink,
  );
  c.restore();
  c.save();
  c.translate(19, 21);
  c.scale(first, first);
  c.translate(-19, -21);
  c.drawPath(
    Path()
      ..moveTo(19, 21)
      ..lineTo(15, 17)
      ..cubicTo(5, 16, 6 + press, 5, 17, 5)
      ..cubicTo(29, 5, 31, 16, 20, 17)
      ..close(),
    ink,
  );
  for (final x in [13.0, 17.5, 22.0]) {
    c.drawCircle(Offset(x, 11), .48, ink);
  }
  c.restore();
}
