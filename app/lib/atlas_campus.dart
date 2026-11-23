import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'house_style.dart';

/// Plays two campus sketches in opposite margins of the graph.
class CampusMargins extends StatefulWidget {
  const CampusMargins({
    super.key,
    required this.activity,
    required this.replay,
    required this.isPanning,
  });

  final Listenable activity;
  final Listenable replay;
  final bool Function() isPanning;

  @override
  State<CampusMargins> createState() => _CampusMarginsState();
}

class _CampusMarginsState extends State<CampusMargins>
    with SingleTickerProviderStateMixin {
  static const _quiet = Duration(seconds: 5);
  static const _settled = Duration(milliseconds: 1600);
  static const _sceneMs = [3600, 3000, 2000, 1800, 1500, 3200];
  static const _rightDelayMs = 180;
  late final _clock = AnimationController(vsync: this);
  Timer? _idle;
  var _pair = 0;
  var _played = false;
  var _allowed = false;

  int get _firstScene => _pair * 2;
  int get _pairMs => math.max(
    _sceneMs[_firstScene],
    _rightDelayMs + _sceneMs[_firstScene + 1],
  );

  @override
  void initState() {
    super.initState();
    widget.activity.addListener(_activity);
    widget.replay.addListener(_play);
    _clock.addStatusListener((status) {
      if (status == AnimationStatus.completed && _allowed && _idle == null) {
        _queue(_quiet);
      }
    });
  }

  @override
  void didUpdateWidget(CampusMargins oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) {
      oldWidget.activity.removeListener(_activity);
      widget.activity.addListener(_activity);
    }
    if (oldWidget.replay != widget.replay) {
      oldWidget.replay.removeListener(_play);
      widget.replay.addListener(_play);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    final tickers = TickerMode.of(context);
    _allowed = !reduced && visible && tickers;
    if (!_allowed) {
      _idle?.cancel();
      _idle = null;
      if (_clock.isAnimating) _clock.value = 1;
    } else if (!_clock.isAnimating && _idle == null) {
      _queue(_settled);
    }
  }

  void _activity() {
    if (!_allowed) return;
    _queue(_settled);
    if (_clock.isAnimating) _clock.value = 1;
  }

  void _queue(Duration delay) {
    _idle?.cancel();
    _idle = Timer(delay, () {
      _idle = null;
      if (widget.isPanning()) {
        _queue(_settled);
        return;
      }
      _play();
    });
  }

  void _play() {
    if (!_allowed) return;
    _idle?.cancel();
    _idle = null;
    if (_played) setState(() => _pair = (_pair + 1) % (_sceneMs.length ~/ 2));
    _played = true;
    _clock.duration = Duration(milliseconds: _pairMs);
    _clock.forward(from: 0);
  }

  @override
  void dispose() {
    widget.activity.removeListener(_activity);
    widget.replay.removeListener(_play);
    _idle?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) {
      if (viewport.maxWidth < 295 || viewport.maxHeight < 200) {
        return const SizedBox.shrink();
      }
      final wide = viewport.maxWidth >= 720;
      final width = wide
          ? 218.0
          : (viewport.maxWidth * .28).clamp(88.0, 160.0).toDouble();
      return Stack(
        children: [
          _sketch(_firstScene, width, wide: wide, left: true),
          _sketch(_firstScene + 1, width, wide: wide, left: false),
        ],
      );
    },
  );

  Widget _sketch(
    int scene,
    double width, {
    required bool wide,
    required bool left,
  }) {
    final delay = left ? 0 : _rightDelayMs;
    return Positioned(
      left: left ? (wide ? 56 : 44) : null,
      right: left ? null : 28,
      bottom: 35,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(width, width * 110 / 218),
            painter: _CampusSketch(
              scene,
              _clock,
              Interval(delay / _pairMs, (delay + _sceneMs[scene]) / _pairMs),
            ),
          ),
        ),
      ),
    );
  }
}

class _CampusSketch extends CustomPainter {
  _CampusSketch(this.scene, this.clock, this.window) : super(repaint: clock);

  final int scene;
  final Animation<double> clock;
  final Interval window;
  static const graphite = Color(0xB3675951);
  static const blue = Color(0xAD2B5078);
  static const red = Color(0xAD732F36);

  static double phase(
    double t,
    double from,
    double to, [
    Curve curve = Curves.easeInOut,
  ]) => Interval(from, to, curve: curve).transform(t);

  static Paint pen(Color color, [double width = 1.65]) => Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static void fill(Canvas c, Path path, Color color) =>
      c.drawPath(path, Paint()..color = color);

  static void paper(
    Canvas c,
    Path path,
    Paint outline, [
    Color color = HouseStyle.paper,
  ]) {
    fill(c, path, color);
    c.drawPath(path, outline);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 218, size.height / 110);
    final t = window.transform(clock.value);
    switch (scene) {
      case 0:
        _catAndBird(canvas, t);
      case 1:
        _beer(canvas, t);
      case 2:
        _pencilAndEraser(canvas, t);
      case 3:
        _scrap(canvas, t);
      case 4:
        _binderClip(canvas, t);
      case 5:
        _paperPlane(canvas, t);
    }
    canvas.restore();
  }

  void _catAndBird(Canvas c, double t) {
    final ink = pen(graphite);
    final flight = phase(t, .36, .76);
    final leap = phase(t, .29, .72);
    final arc = math.sin(math.pi * leap);
    final coil = math.sin(math.pi * phase(t, 0, .35));
    final impact = math.sin(math.pi * phase(t, .65, .87));
    c.drawPath(
      Path()
        ..moveTo(12, 88)
        ..quadraticBezierTo(48, 87, 67, 89)
        ..moveTo(125, 89)
        ..quadraticBezierTo(145, 86, 164, 88),
      pen(graphite.withValues(alpha: .32), 1.15),
    );
    c.save();
    c.translate(38 + 81 * leap, 72 - 26 * arc + 3 * coil);
    c.scale(1 + .29 * arc + .16 * impact, 1 - .24 * coil - .25 * impact);
    c.rotate(-.23 * arc);
    final tail = Path()
      ..moveTo(-16, 4)
      ..cubicTo(-24, 7 - 9 * coil, -31, -10, -27 - 5 * arc, -17 + 4 * coil)
      ..quadraticBezierTo(-25, -24 + 7 * coil, -21, -20 + 5 * coil);
    c.drawPath(tail, ink);
    paper(
      c,
      Path()
        ..moveTo(-17, 1)
        ..cubicTo(-10, -10, 4, -9, 9, -4)
        ..lineTo(11, -10)
        ..lineTo(13, -19)
        ..lineTo(19, -14)
        ..lineTo(24, -17)
        ..lineTo(25, -8)
        ..quadraticBezierTo(33, -5 - 5 * leap, 28, 1 - 4 * leap)
        ..quadraticBezierTo(23, 5, 16, 5)
        ..quadraticBezierTo(10, 11, -7, 9)
        ..quadraticBezierTo(-19, 10, -17, 1)
        ..close(),
      ink,
    );
    c.drawCircle(Offset(22, -8 - 2.5 * leap), 1.05, Paint()..color = graphite);
    c.drawPath(
      Path()
        ..moveTo(25, -5)
        ..lineTo(33, -7)
        ..moveTo(25, -3)
        ..lineTo(33, -2),
      pen(graphite, 1.05),
    );
    c.drawPath(
      Path()
        ..moveTo(-12, 7)
        ..quadraticBezierTo(-10 - 11 * arc, 13, -18 - 8 * arc, 16 - 4 * arc)
        ..moveTo(10, 7)
        ..quadraticBezierTo(
          15 + 11 * arc,
          14 - 9 * arc,
          19 + 13 * arc,
          16 - 12 * arc,
        ),
      ink,
    );
    c.restore();

    final peck =
        math.sin(4 * math.pi * phase(t, 0, .32)) * (flight == 0 ? .18 : 0);
    final flap = math.sin(8 * math.pi * flight) * math.sin(math.pi * flight);
    c.save();
    c.translate(
      133 + 59 * flight,
      76 - 41 * flight - 14 * math.sin(math.pi * flight),
    );
    c.rotate(peck - .23 * math.sin(math.pi * flight));
    final wing = pen(blue);
    paper(
      c,
      Path()
        ..moveTo(-12, 2)
        ..quadraticBezierTo(-5, -10, 3, -4)
        ..quadraticBezierTo(7, -11, 12, -6)
        ..lineTo(16, -4)
        ..lineTo(12, -2)
        ..quadraticBezierTo(9, 7, 1, 6)
        ..lineTo(-12, 8)
        ..lineTo(-8, 4)
        ..close(),
      wing,
    );
    c.drawPath(
      Path()
        ..moveTo(4, 1)
        ..quadraticBezierTo(-4, -3 - flap * 16, -7, -2 - flap * 21)
        ..quadraticBezierTo(-4, 5 - flap * 2, 4, 1),
      wing,
    );
    c.drawCircle(const Offset(10, -5), .8, Paint()..color = blue);
    if (flight < .09) {
      final stance = 1 - flight / .09;
      c.drawLine(const Offset(0, 6), Offset(-2, 6 + stance * 5), wing);
      c.drawLine(const Offset(4, 6), Offset(5, 6 + stance * 5), wing);
    }
    c.restore();
  }

  void _beer(Canvas c, double t) {
    final tilt = phase(t, 0, .25) * (1 - phase(t, .74, .96));
    final level = phase(t, .24, .79);
    final wave = math.sin(16 * math.pi * t) * tilt;
    final ink = pen(graphite);
    final amber = pen(const Color(0xBB9A5F26));
    final glass = Path()
      ..moveTo(124, 48)
      ..lineTo(165, 48)
      ..lineTo(161, 91)
      ..quadraticBezierTo(144, 95, 129, 91)
      ..close();
    c.drawPath(
      Path()
        ..moveTo(164, 55)
        ..cubicTo(186, 49, 185, 79, 162, 82)
        ..moveTo(164, 60)
        ..cubicTo(177, 57, 176, 74, 163, 76),
      ink,
    );
    paper(c, glass, ink);
    c.save();
    c.clipPath(glass);
    final surface = 89 - 30 * level;
    fill(
      c,
      Path()
        ..moveTo(122, surface)
        ..quadraticBezierTo(145, surface + wave * 4, 168, surface - wave)
        ..lineTo(168, 94)
        ..lineTo(122, 94)
        ..close(),
      const Color(0x66D9943A),
    );
    if (level > .04) {
      c.drawPath(
        Path()
          ..moveTo(123, surface)
          ..quadraticBezierTo(145, surface + wave * 4, 166, surface - wave),
        amber,
      );
      for (var i = 0; i < 3; i++) {
        final foam =
            2.0 + math.sin(12 * math.pi * t + i) * tilt * 2 + level * 2;
        final x = 132 + i * 11.0;
        c.drawPath(
          Path()
            ..moveTo(x - 5, surface)
            ..quadraticBezierTo(x, surface - foam * 2, x + 5, surface - 1),
          pen(graphite, 1.1),
        );
      }
    }
    c.restore();
    c.save();
    const bottlePivot = Offset(99, 38);
    final angle = -1.23 + 1.64 * tilt;
    c.translate(bottlePivot.dx, bottlePivot.dy);
    c.rotate(angle);
    paper(
      c,
      Path()
        ..moveTo(-57, -9)
        ..lineTo(-27, -10)
        ..quadraticBezierTo(-16, -8, -12, -4)
        ..lineTo(0, -4)
        ..lineTo(0, 4)
        ..lineTo(-12, 4)
        ..quadraticBezierTo(-18, 10, -29, 10)
        ..lineTo(-57, 9)
        ..quadraticBezierTo(-60, 8, -60, 5)
        ..lineTo(-60, -5)
        ..quadraticBezierTo(-60, -9, -57, -9)
        ..close(),
      ink,
      const Color(0xFFF3E9D4),
    );
    c.drawPath(
      Path()
        ..moveTo(-48, -8)
        ..lineTo(-48, 8)
        ..moveTo(-33, -8)
        ..lineTo(-33, 8)
        ..moveTo(-46, 2)
        ..quadraticBezierTo(-41, -4, -36, 1),
      amber,
    );
    c.restore();
    final stream = phase(t, .2, .31) * (1 - phase(t, .68, .82));
    if (stream > .01) {
      c.drawPath(
        Path()
          ..moveTo(bottlePivot.dx, bottlePivot.dy + 2)
          ..cubicTo(118, 39 + 3 * wave, 137 - 3 * wave, 48, 140, surface),
        pen(const Color(0xC1B76E29), 1 + 3.2 * stream),
      );
    }
  }

  void _pencilAndEraser(Canvas c, double t) {
    final roll = phase(t, 0, .55, Curves.easeInCubic);
    final impact = math.sin(math.pi * phase(t, .46, .76));
    final shift = phase(t, .48, .85) * 12;
    final ink = pen(graphite);
    c.drawPath(
      Path()
        ..moveTo(22, 77)
        ..quadraticBezierTo(90, 75, 196, 78),
      pen(graphite.withValues(alpha: .34), 1.1),
    );
    c.save();
    c.translate(28 + 75 * roll, 67);
    c.rotate(math.sin(5 * math.pi * roll) * (1 - roll) * .16);
    final pencil = Path()
      ..moveTo(0, -6)
      ..lineTo(42, -6)
      ..lineTo(55, 0)
      ..lineTo(42, 6)
      ..lineTo(0, 6)
      ..close();
    paper(c, pencil, ink);
    final facet = 3.3 * math.sin(4 * math.pi * roll + .2);
    c.drawPath(
      Path()
        ..moveTo(9, -5)
        ..lineTo(9, 5)
        ..moveTo(10, facet)
        ..lineTo(42, facet)
        ..moveTo(42, -5)
        ..lineTo(42, 5)
        ..moveTo(50, -2)
        ..lineTo(50, 2),
      pen(red),
    );
    c.restore();
    c.save();
    c.translate(157 + shift, 74);
    c.rotate(-.12 * math.sin(2 * math.pi * phase(t, .49, .91)));
    c.scale(1 - .23 * impact, 1 + .17 * impact);
    paper(
      c,
      Path()
        ..moveTo(0, 0)
        ..lineTo(2, -18)
        ..lineTo(25, -18)
        ..lineTo(27, -3)
        ..lineTo(4, 2)
        ..close(),
      pen(red),
      const Color(0xFFF1E4DA),
    );
    c.drawLine(const Offset(8, -17), const Offset(6, 1), pen(red, 1.2));
    c.restore();
    if (impact > .1) {
      c.drawLine(const Offset(151, 46), Offset(144 - 4 * impact, 43), ink);
      c.drawLine(const Offset(158, 43), Offset(157, 36 - 4 * impact), ink);
    }
  }

  void _scrap(Canvas c, double t) {
    final swell = math.sin(math.pi * t);
    final curl = math.sin(4 * math.pi * t) * swell * 12;
    final paperEdge = Path()
      ..moveTo(54, 38)
      ..lineTo(149, 37)
      ..quadraticBezierTo(168, 58 - curl, 164, 84 - curl)
      ..quadraticBezierTo(113, 76 + curl * .3, 54, 84)
      ..close();
    paper(c, paperEdge, pen(graphite), const Color(0xFFF9F0E0));
    for (var i = 0; i < 3; i++) {
      final y = 50 + 8 * i.toDouble();
      c.drawPath(
        Path()
          ..moveTo(70, y)
          ..cubicTo(
            91,
            y + 2,
            116,
            y - curl * .24,
            148 - i * 9,
            y - curl * .65,
          ),
        pen(blue, 1.25),
      );
    }
    c.drawPath(
      Path()
        ..moveTo(160, 82 - curl)
        ..quadraticBezierTo(155, 71 - curl * .2, 148, 78 - curl * .3),
      pen(graphite, 1.15),
    );
  }

  void _binderClip(Canvas c, double t) {
    final open = math.sin(math.pi * phase(t, 0, .68));
    final thump = math.sin(2 * math.pi * phase(t, .54, 1)) * (1 - t);
    final paperEdge = Path()
      ..moveTo(61, 53)
      ..lineTo(155, 57)
      ..quadraticBezierTo(157, 68 + thump * 9, 147, 89)
      ..lineTo(59, 85)
      ..close();
    paper(c, paperEdge, pen(graphite), const Color(0xFFF9F0E0));
    c.drawPath(
      Path()
        ..moveTo(83, 42)
        ..lineTo(131, 44)
        ..lineTo(126, 60 + open * 10)
        ..lineTo(86, 58 + open * 10)
        ..close(),
      pen(red, 2.35),
    );
    for (final side in [-1.0, 1.0]) {
      final x = 108 + side * 10;
      c.drawPath(
        Path()
          ..moveTo(x, 47)
          ..cubicTo(
            x + side * (13 + open * 5),
            18 + open * 7,
            x - side * 9,
            16 + open * 7,
            x - side,
            44,
          ),
        pen(graphite),
      );
    }
  }

  void _paperPlane(Canvas c, double t) {
    final first = phase(t, 0, .23);
    final second = phase(t, .18, .39);
    final third = phase(t, .34, .55);
    final fly = phase(t, .57, 1, Curves.easeInQuad);
    final flutter = math.sin(18 * math.pi * fly) * 4 * fly;
    final shape = Path()
      ..moveTo(-31 + 9 * first, -18 + 12 * first)
      ..lineTo(31 - 3 * second, -18 + 17 * second)
      ..lineTo(30 - 38 * third, 15 + flutter)
      ..lineTo(-30 + 24 * third, 15 - 10 * third)
      ..close();
    if (fly > .01) {
      final trail = pen(blue.withValues(alpha: .35), 1.2);
      for (var i = 0; i < 5; i++) {
        final distance = fly * 180 - 25 - i * 14;
        if (distance < 0) break;
        c.drawLine(
          Offset(56 + distance, 66 - distance * .25),
          Offset(62 + distance, 64 - distance * .25),
          trail,
        );
      }
    }
    c.save();
    c.translate(56 + fly * 180, 63 - fly * 49);
    c.rotate(-.10 - .15 * fly);
    final ink = pen(blue);
    paper(c, shape, ink, const Color(0xFFFBF3E5));
    if (first > 0) {
      c.drawLine(
        Offset(-31 + 9 * first, -18 + 12 * first),
        Offset(-22 + 25 * first, -6 + 7 * first),
        ink,
      );
    }
    if (second > 0) {
      c.drawPath(
        Path()
          ..moveTo(3, 1)
          ..lineTo(3 + 25 * second, 1 - 2 * second)
          ..moveTo(3, 1)
          ..lineTo(3 - 9 * third, 1 + 4 * third),
        ink,
      );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_CampusSketch oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.clock != clock ||
      oldDelegate.window.begin != window.begin ||
      oldDelegate.window.end != window.end;
}
