import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'house_style.dart';

/// Small ink drawings that share the notebook's animation clock.
enum Doodle { pencil, paperPlane, inkBlot }

class NotebookDoodle extends StatelessWidget {
  const NotebookDoodle(this.kind, this.motion, {super.key});

  final Doodle kind;
  final Animation<double> motion;
  static const size = Size(112, 100);

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(size: size, painter: _DoodlePainter(kind, motion)),
    ),
  );
}

class DoodleRail extends StatelessWidget {
  const DoodleRail(this.motion, {super.key});

  final Animation<double> motion;
  static const width = 132.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Attach the drawings to the page, so they scroll past like real margins.
      const gap = 380.0;
      final count = math.max(
        0,
        ((constraints.maxHeight - NotebookDoodle.size.height - 14) / gap)
                .floor() +
            1,
      );
      return Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              right: 0,
              top: 14 + gap * i,
              child: NotebookDoodle(
                Doodle.values[i % Doodle.values.length],
                motion,
              ),
            ),
        ],
      );
    },
  );
}

class _DoodlePainter extends CustomPainter {
  _DoodlePainter(this.kind, this.motion) : super(repaint: motion);

  final Doodle kind;
  final Animation<double> motion;

  static Paint _pen(Color color, [double width = 1.7]) => Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  static void _paperShape(Canvas canvas, Path path, Paint pen) {
    canvas.drawPath(path, Paint()..color = HouseStyle.paper);
    canvas.drawPath(path, pen);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (kind) {
      case Doodle.pencil:
        _pencil(canvas, const Interval(.0, .72).transform(motion.value));
      case Doodle.paperPlane:
        _plane(canvas, const Interval(.14, 1).transform(motion.value));
      case Doodle.inkBlot:
        _blot(canvas, const Interval(.22, .90).transform(motion.value));
    }
    canvas.restore();
  }

  void _pencil(Canvas canvas, double t) {
    final ink = _pen(HouseStyle.ink);
    final red = _pen(HouseStyle.binder);
    final scratch = _pen(HouseStyle.pen.withValues(alpha: .6), 1.25);
    canvas.drawPath(
      Path()
        ..moveTo(14, 83)
        ..quadraticBezierTo(34, 85, 49, 81)
        ..moveTo(51, 81)
        ..lineTo(60, 76)
        ..lineTo(61, 85)
        ..lineTo(71, 79)
        ..quadraticBezierTo(79, 82, 93, 80),
      scratch,
    );

    // Two hops return the pencil to the same pose between bursts.
    final beats = t * 2;
    final bounce = math.sin(math.pi * (beats % 1));
    final bound = math.sin(math.pi * t);
    final launch = math.sin(4 * math.pi * t);
    if (bounce > .3) {
      final flick = _pen(
        HouseStyle.binder.withValues(alpha: bounce * .75),
        1.3,
      );
      canvas.drawLine(
        Offset(26 + 33 * bound, 69),
        Offset(19 + 33 * bound, 71),
        flick,
      );
      canvas.drawLine(
        Offset(27 + 33 * bound, 75),
        Offset(23 + 33 * bound, 77),
        flick,
      );
    }
    canvas.save();
    canvas.translate(39 + 29 * bound, 69 - 24 * bounce);
    canvas.rotate(-.21 + .42 * launch);
    final stretch = .94 + .20 * bounce - .10 * math.pow(launch.abs(), 4);
    canvas.scale(2 - stretch, stretch);

    final body = Path()
      ..moveTo(-7, 1)
      ..lineTo(-7, -35)
      ..quadraticBezierTo(-6, -41, 0, -41)
      ..quadraticBezierTo(7, -41, 7, -35)
      ..lineTo(7, 1)
      ..lineTo(0, 11)
      ..close();
    _paperShape(canvas, body, ink);
    canvas.drawPath(
      Path()
        ..moveTo(-6, -32)
        ..quadraticBezierTo(0, -30, 6, -32)
        ..moveTo(-6, -36)
        ..quadraticBezierTo(0, -34, 6, -36),
      red,
    );
    canvas.drawLine(const Offset(-6, 0), const Offset(6, 0), ink);
    canvas.drawLine(const Offset(-3, -29), const Offset(-3, -6), scratch);
    canvas.drawCircle(
      const Offset(2, -17),
      1.15,
      Paint()..color = HouseStyle.ink,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-4, 2)
        ..quadraticBezierTo(-11, 6 - 4 * launch, -11, 13)
        ..lineTo(-16, 13)
        ..moveTo(4, 2)
        ..quadraticBezierTo(11, 6 + 4 * launch, 11, 13)
        ..lineTo(16, 13),
      ink,
    );
    canvas.restore();
  }

  void _plane(Canvas canvas, double t) {
    final ink = _pen(HouseStyle.pen);
    final trail = _pen(HouseStyle.pen.withValues(alpha: .5), 1.15);
    final theta = 2 * math.pi * t;
    Offset route(double angle) =>
        Offset(56 + 26 * math.sin(angle), 56 - 22 * math.sin(angle / 2));

    if (t > 0 && t < 1) {
      for (var i = 1; i <= 5; i++) {
        final angle = theta - i * .24;
        if (angle < 0) break;
        canvas.drawLine(route(angle), route(angle - .11), trail);
      }
    } else {
      canvas.drawLine(const Offset(19, 66), const Offset(25, 64), trail);
      canvas.drawLine(const Offset(29, 63), const Offset(34, 62), trail);
    }

    final center = route(theta);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.16 - .60 * math.sin(theta));
    _paperShape(
      canvas,
      Path()
        ..moveTo(-20, -8)
        ..quadraticBezierTo(2, -8, 23, -1)
        ..lineTo(-8, 13)
        ..lineTo(-6, 5)
        ..close(),
      ink,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-20, -8)
        ..lineTo(0, 1)
        ..lineTo(23, -1)
        ..moveTo(0, 1)
        ..lineTo(-6, 5),
      ink,
    );
    canvas.restore();
  }

  void _blot(Canvas canvas, double t) {
    final ink = _pen(HouseStyle.binder);
    final swell = math.pow(math.sin(math.pi * t), 3).toDouble();
    final jiggle = math.sin(t * math.pi * 8) * swell;
    final shape = Path();
    const points = 10;
    for (var i = 0; i < points; i++) {
      final angle = i * 2 * math.pi / points - math.pi / 2;
      final radius = 13 + (i.isEven ? 13 * swell : -4 * swell);
      final x = 56 + math.cos(angle + jiggle * .19) * radius;
      final y = 55 - 12 * swell + math.sin(angle + jiggle * .19) * radius;
      if (i == 0) {
        shape.moveTo(x, y);
      } else {
        shape.lineTo(x, y);
      }
    }
    _paperShape(canvas, shape..close(), ink);
    canvas.drawLine(
      Offset(50, 56 - 12 * swell),
      Offset(53, 53 - 12 * swell),
      ink,
    );
    canvas.drawLine(
      Offset(59, 56 - 12 * swell),
      Offset(62, 53 - 12 * swell),
      ink,
    );
    final scratches = _pen(HouseStyle.pen.withValues(alpha: .6), 1.3);
    canvas.drawPath(
      Path()
        ..moveTo(30 - 5 * swell, 42)
        ..lineTo(25 - 5 * swell, 39)
        ..lineTo(22 - 5 * swell, 45)
        ..lineTo(16 - 5 * swell, 42)
        ..moveTo(81 + 5 * swell, 57)
        ..lineTo(88 + 5 * swell, 54)
        ..moveTo(80 + 5 * swell, 65)
        ..lineTo(85 + 5 * swell, 66),
      scratches,
    );
  }

  @override
  bool shouldRepaint(_DoodlePainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.motion != motion;
}
