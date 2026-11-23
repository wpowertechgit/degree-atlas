import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'house_style.dart';

class AtlasDesk extends CustomPainter {
  AtlasDesk({
    required this.view,
    required this.drag,
    required this.settle,
    required this.flip,
  }) : super(repaint: Listenable.merge([view, drag, settle, flip]));

  final TransformationController view;
  final ValueNotifier<Offset> drag;
  final Animation<double> settle, flip;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF765348), Color(0xFF5F4139)],
          end: Alignment.bottomRight,
        ).createShader(bounds),
    );
    final camera = view.value.getTranslation();
    final small = size.width < 600;
    final rim = small ? 5.0 : 10.0;
    final slip = small
        ? Offset.zero
        : Offset(math.sin(camera.x / 180) * 5, math.sin(camera.y / 180) * 4);
    final lift = math.sin(math.pi * flip.value);
    final flex = drag.value * (1 - Curves.easeOut.transform(settle.value));
    final sheet = bounds.deflate(rim).shift(slip - Offset(8 * lift, 0));
    final outline = Path()
      ..moveTo(sheet.left, sheet.top + 1)
      ..quadraticBezierTo(
        sheet.center.dx,
        sheet.top + flex.dy,
        sheet.right,
        sheet.top,
      )
      ..quadraticBezierTo(
        sheet.right + flex.dx,
        sheet.center.dy,
        sheet.right,
        sheet.bottom,
      )
      ..quadraticBezierTo(
        sheet.center.dx,
        sheet.bottom - flex.dy,
        sheet.left,
        sheet.bottom - 1,
      )
      ..close();

    if (!small) {
      final scrap = Offset(size.width - 117, 14) + slip * .45;
      canvas.save();
      canvas.translate(scrap.dx, scrap.dy);
      canvas.rotate(.10);
      canvas.drawRRect(
        RRect.fromLTRBR(0, -20, 83, 36, const Radius.circular(2)),
        Paint()..color = HouseStyle.pageEdge,
      );
      canvas.restore();
      canvas.drawPath(
        Path()
          ..moveTo(0, size.height - 60)
          ..quadraticBezierTo(57, size.height - 71, 118, size.height)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = HouseStyle.binder,
      );
    }
    canvas.drawShadow(outline, HouseStyle.ink, 3, false);
    canvas.drawPath(outline, Paint()..color = HouseStyle.paper);
    canvas.save();
    canvas.clipPath(outline);
    final ruling = Paint()..color = HouseStyle.ruling;
    for (
      var y = sheet.top + 22;
      y < sheet.bottom;
      y += HouseStyle.ruleSpacing
    ) {
      canvas.drawLine(
        Offset(sheet.left - 8, y),
        Offset(sheet.right + 8, y),
        ruling,
      );
    }
    final margin = sheet.left + (small ? 22 : 43);
    canvas.drawLine(
      Offset(margin, sheet.top),
      Offset(margin, sheet.bottom),
      Paint()..color = HouseStyle.margin,
    );
    if (!small) {
      final points = [
        Offset(sheet.left + 24, sheet.height * .31),
        Offset(sheet.right - 75, sheet.height * .23),
        Offset(sheet.width * .64, sheet.bottom - 26),
      ];
      final pull = drag.value.dx < 0
          ? 0
          : (drag.value.dy.abs() > drag.value.dx.abs() ? 2 : 1);
      for (var i = 0; i < points.length; i++) {
        final spread = i == pull ? 4 * (1 - settle.value) : 0.0;
        _crease(canvas, points[i], i == 1 ? -.35 : .24, spread);
      }
    }
    canvas.restore();

    if (lift > .001) {
      final corner = sheet.topRight;
      final width = 106 * lift;
      final fold = Path()
        ..moveTo(corner.dx - width, corner.dy)
        ..quadraticBezierTo(
          corner.dx - width * .11,
          corner.dy - 11 * lift,
          corner.dx,
          corner.dy + width * .69,
        )
        ..quadraticBezierTo(
          corner.dx - width * .32,
          corner.dy + width * .32,
          corner.dx - width,
          corner.dy,
        )
        ..close();
      canvas.drawShadow(fold, HouseStyle.graphite, 7 * lift, false);
      canvas.drawPath(fold, Paint()..color = HouseStyle.pageEdge);
      canvas.drawPath(
        fold,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = HouseStyle.margin,
      );
    }
  }

  void _crease(Canvas canvas, Offset point, double angle, double spread) {
    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(angle);
    for (final offset in [-1.0, 1.0]) {
      final sign = offset * (1.2 + spread);
      final paint = Paint()
        ..color = (offset < 0 ? HouseStyle.graphite : Colors.white).withValues(
          alpha: offset < 0 ? .12 : .82,
        )
        ..strokeWidth = offset < 0 ? 1.2 : 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(-18, 2)
          ..cubicTo(4, sign - 10, 40, sign + 1, 59, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(AtlasDesk oldDelegate) =>
      oldDelegate.view != view ||
      oldDelegate.drag != drag ||
      oldDelegate.settle != settle ||
      oldDelegate.flip != flip;
}

class CourseCardClip extends CustomClipper<Path> {
  const CourseCardClip(this.bend);
  final double bend;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h - bend * 3)
      ..quadraticBezierTo(w * .64, h + bend * 4, 0, h)
      ..close();
  }

  @override
  bool shouldReclip(CourseCardClip oldClipper) => oldClipper.bend != bend;
}

class CardLeader extends CustomPainter {
  const CardLeader(this.node, this.card, this.progress);
  final Offset node, card;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Path()
      ..moveTo(node.dx, node.dy)
      ..quadraticBezierTo(
        (node.dx + card.dx) * .5,
        node.dy - 12,
        card.dx,
        card.dy,
      );
    final route = line.computeMetrics().firstOrNull;
    if (route == null) return;
    canvas.drawPath(
      route.extractPath(0, route.length * progress),
      Paint()
        ..color = HouseStyle.graphite.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(CardLeader oldDelegate) =>
      oldDelegate.node != node ||
      oldDelegate.card != card ||
      oldDelegate.progress != progress;
}

/// Opens a paper-colored corner from the card's bounds into the full notebook.
class NotebookUnfold extends StatelessWidget {
  const NotebookUnfold({
    super.key,
    required this.origin,
    required this.animation,
    required this.child,
  });

  final Rect origin;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final screen = constraints.biggest;
      final target = Rect.fromCenter(
        center: screen.center(Offset.zero),
        width: math.max(
          0.0,
          math.min(HouseStyle.readingWidth + 48, screen.width - 24),
        ),
        height: math.max(0.0, math.min(screen.height * .9, screen.height - 40)),
      );
      return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, content) {
          final t = Curves.easeOutCubic.transform(animation.value);
          final page = Rect.lerp(origin, target, t)!;
          final curl = math.sin(math.pi * t) * 32;
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: Curves.easeIn.transform(t),
                child: ClipPath(
                  clipBehavior: t == 1 ? Clip.none : Clip.antiAlias,
                  clipper: _UnfoldClip(page, curl),
                  child: content,
                ),
              ),
              IgnorePointer(
                child: CustomPaint(painter: _UnfoldPaper(page, curl, t)),
              ),
            ],
          );
        },
      );
    },
  );
}

class _UnfoldClip extends CustomClipper<Path> {
  const _UnfoldClip(this.page, this.curl);
  final Rect page;
  final double curl;

  @override
  Path getClip(Size size) => _unfoldPath(page, curl);

  @override
  bool shouldReclip(_UnfoldClip oldClipper) =>
      oldClipper.page != page || oldClipper.curl != curl;
}

Path _unfoldPath(Rect page, double curl) => Path()
  ..moveTo(page.left, page.top)
  ..lineTo(page.right - curl, page.top)
  ..quadraticBezierTo(
    page.right - curl * .25,
    page.top + curl * .12,
    page.right,
    page.top + curl,
  )
  ..lineTo(page.right, page.bottom)
  ..lineTo(page.left, page.bottom)
  ..close();

class _UnfoldPaper extends CustomPainter {
  const _UnfoldPaper(this.page, this.curl, this.progress);
  final Rect page;
  final double curl, progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _unfoldPath(page, curl),
      Paint()..color = HouseStyle.paper.withValues(alpha: (1 - progress) * .94),
    );
    final corner = Path()
      ..moveTo(page.right - curl, page.top)
      ..quadraticBezierTo(
        page.right - curl * .2,
        page.top + curl * .12,
        page.right,
        page.top + curl,
      )
      ..quadraticBezierTo(
        page.right - curl * .8,
        page.top + curl * .82,
        page.right - curl,
        page.top,
      )
      ..close();
    canvas.drawPath(corner, Paint()..color = HouseStyle.pageEdge);
  }

  @override
  bool shouldRepaint(_UnfoldPaper oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.page != page;
}
