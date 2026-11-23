import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show LineMetrics;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'house_style.dart';
import 'notebook_doodles.dart';

class CourseNotebook extends StatefulWidget {
  const CourseNotebook({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.entranceDelay = Duration.zero,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final Duration entranceDelay;

  @override
  State<CourseNotebook> createState() => _CourseNotebookState();
}

class _CourseNotebookState extends State<CourseNotebook>
    with TickerProviderStateMixin {
  late final _intro = AnimationController(
    vsync: this,
    duration: HouseStyle.intro,
  );
  late final _doodles = AnimationController(
    vsync: this,
    duration: HouseStyle.doodleBurst,
    value: 1,
  );
  Timer? _nextDoodle;
  Timer? _startTitle;
  final _scroll = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final activeRoute = ModalRoute.isCurrentOf(context) ?? true;
    final tickersEnabled = TickerMode.of(context);
    if (reducedMotion) {
      _startTitle?.cancel();
      _startTitle = null;
      _intro.value = 1;
    } else if (_intro.isDismissed && _startTitle == null) {
      if (widget.entranceDelay == Duration.zero) {
        _intro.forward();
      } else {
        _startTitle = Timer(widget.entranceDelay, () {
          _startTitle = null;
          _intro.forward();
        });
      }
    }
    if (reducedMotion || !activeRoute || !tickersEnabled) {
      _nextDoodle?.cancel();
      _nextDoodle = null;
      _doodles.value = 1;
    } else if (_nextDoodle == null) {
      _scheduleDoodles(HouseStyle.firstDoodle);
    }
  }

  void _scheduleDoodles(Duration delay) {
    _nextDoodle = Timer(delay, () {
      _doodles.forward(from: 0);
      _scheduleDoodles(HouseStyle.doodleInterval);
    });
  }

  @override
  void dispose() {
    _startTitle?.cancel();
    _nextDoodle?.cancel();
    _doodles.dispose();
    _intro.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyMedium: theme.textTheme.bodyMedium?.merge(HouseStyle.body),
          headlineMedium: HouseStyle.noteHeading,
          titleLarge: HouseStyle.noteHeading.copyWith(fontSize: 22),
        ),
      ),
      child: ColoredBox(
        color: HouseStyle.desk,
        child: LayoutBuilder(
          builder: (context, viewport) {
            final narrow = viewport.maxWidth < 560;
            final outer = HouseStyle.spacing * (narrow ? 1 : 3);
            final gutter = narrow ? 19.0 : 35.0;
            final contentLeft = gutter + HouseStyle.spacing * (narrow ? 1 : 3);
            final contentRight =
                HouseStyle.spacing *
                (widget.onClose != null ? 7 : (narrow ? 2 : 5));
            final sheetWidth = math.min(
              HouseStyle.readingWidth,
              viewport.maxWidth - outer * 2,
            );
            final hasDoodleRail =
                sheetWidth - contentLeft - contentRight >= 680;
            return Stack(
              children: [
                Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.all(outer),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: HouseStyle.readingWidth,
                          minHeight: math.max(
                            0.0,
                            viewport.maxHeight - 2 * outer,
                          ),
                        ),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: HouseStyle.paper,
                            boxShadow: [
                              BoxShadow(
                                color: HouseStyle.pageEdge,
                                offset: Offset(2, 3),
                              ),
                              BoxShadow(
                                color: HouseStyle.pageEdge,
                                offset: Offset(4, 5),
                              ),
                            ],
                          ),
                          child: CustomPaint(
                            painter: _NotebookPaper(gutter),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                contentLeft,
                                28,
                                contentRight,
                                52,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      SvgPicture.asset(
                                        HouseStyle.mark,
                                        width: 24,
                                        height: 20,
                                      ),
                                      const SizedBox(width: HouseStyle.spacing),
                                      const Flexible(
                                        child: Text(
                                          'EMAF / HOUSE COPY',
                                          style: HouseStyle.label,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: HouseStyle.spacing * 2,
                                  ),
                                  LayoutBuilder(
                                    builder: (context, header) {
                                      final hasMargin = header.maxWidth >= 540;
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _WritingTitle(
                                              title: widget.title,
                                              intro: _intro,
                                              compact: narrow,
                                            ),
                                          ),
                                          if (hasMargin) ...[
                                            const SizedBox(
                                              width: HouseStyle.spacing * 3,
                                            ),
                                            RepaintBoundary(
                                              child: CustomPaint(
                                                size: const Size(108, 76),
                                                painter: _MarginSketch(
                                                  _intro,
                                                  book: true,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                  RepaintBoundary(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: CustomPaint(
                                        size: const Size(124, 12),
                                        painter: _MarginSketch(
                                          _intro,
                                          book: false,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: HouseStyle.spacing * 2,
                                  ),
                                  AnimatedBuilder(
                                    animation: _intro,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (hasDoodleRail)
                                          Stack(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: DoodleRail.width,
                                                ),
                                                child: widget.child,
                                              ),
                                              Positioned(
                                                top: 50,
                                                right: 0,
                                                bottom: 0,
                                                width: DoodleRail.width,
                                                child: DoodleRail(_doodles),
                                              ),
                                            ],
                                          )
                                        else
                                          widget.child,
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: NotebookDoodle(
                                            hasDoodleRail
                                                ? Doodle.paperPlane
                                                : Doodle.inkBlot,
                                            _doodles,
                                          ),
                                        ),
                                      ],
                                    ),
                                    builder: (context, child) {
                                      final amount = HouseStyle.noteDrop
                                          .transform(_intro.value);
                                      return IgnorePointer(
                                        ignoring: amount == 0,
                                        child: Opacity(
                                          opacity: amount,
                                          child: Transform.translate(
                                            offset: Offset(
                                              0,
                                              -14 * (1 - amount),
                                            ),
                                            child: child,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.onClose != null)
                  Positioned(
                    top: outer + 4,
                    right: outer + 8,
                    child: IconButton.filled(
                      tooltip: 'Close notebook',
                      style: IconButton.styleFrom(
                        backgroundColor: HouseStyle.paper,
                        foregroundColor: HouseStyle.binder,
                      ),
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WritingTitle extends StatelessWidget {
  const _WritingTitle({
    required this.title,
    required this.intro,
    required this.compact,
  });

  final String title;
  final Animation<double> intro;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style
          .merge(HouseStyle.heading.copyWith(fontSize: compact ? 31 : null));
      final direction = Directionality.of(context);
      final locale = Localizations.maybeLocaleOf(context);
      final scale = MediaQuery.textScalerOf(context);
      final layout = TextPainter(
        text: TextSpan(text: title, style: style),
        textDirection: direction,
        textScaler: scale,
        locale: locale,
      )..layout(maxWidth: constraints.maxWidth);
      final lines = layout.computeLineMetrics();
      layout.dispose();
      return Semantics(
        header: true,
        label: title,
        child: ExcludeSemantics(
          child: ClipPath(
            clipper: _WritingClip(intro, lines, direction),
            child: Text(
              title,
              style: style,
              textDirection: direction,
              textAlign: TextAlign.start,
              textScaler: scale,
              locale: locale,
            ),
          ),
        ),
      );
    },
  );
}

class _WritingClip extends CustomClipper<Path> {
  _WritingClip(this.intro, this.lines, this.direction) : super(reclip: intro);

  final Animation<double> intro;
  final List<LineMetrics> lines;
  final TextDirection direction;

  @override
  Path getClip(Size size) {
    final progress = HouseStyle.titleWrite.transform(intro.value);
    final path = Path();
    if (progress == 1) return path..addRect(Offset.zero & size);
    var remaining =
        progress * lines.fold(0.0, (width, line) => width + line.width);
    for (final line in lines) {
      if (remaining <= 0) break;
      final visible = math.min(remaining, line.width);
      final right = line.left + line.width + 3;
      final left = math.max(0.0, line.left - 3);
      path.addRect(
        Rect.fromLTRB(
          direction == TextDirection.ltr ? left : right - visible - 6,
          line.baseline - line.ascent,
          direction == TextDirection.ltr ? left + visible + 6 : right,
          line.baseline + line.descent,
        ),
      );
      remaining -= line.width;
    }
    return path;
  }

  @override
  bool shouldReclip(_WritingClip oldClipper) => true;
}

class _NotebookPaper extends CustomPainter {
  const _NotebookPaper(this.gutter);

  final double gutter;

  @override
  void paint(Canvas canvas, Size size) {
    final pencil = Paint()..color = HouseStyle.ruling;
    for (var y = 0.5; y < size.height; y += HouseStyle.ruleSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pencil);
    }
    canvas.drawLine(
      Offset(gutter, 0),
      Offset(gutter, size.height),
      Paint()..color = HouseStyle.margin,
    );
    for (final y in [28.0, 150.0, 272.0]) {
      if (y >= size.height) break;
      final center = Offset(gutter * 0.48, y);
      final hole = gutter > 20 ? 4.75 : 3.0;
      canvas.drawCircle(
        center,
        hole + 0.7,
        Paint()..color = HouseStyle.pageEdge,
      );
      canvas.drawCircle(center, hole, Paint()..color = HouseStyle.desk);
    }
  }

  @override
  bool shouldRepaint(_NotebookPaper oldDelegate) =>
      oldDelegate.gutter != gutter;
}

class _MarginSketch extends CustomPainter {
  _MarginSketch(this.intro, {required this.book}) : super(repaint: intro);

  final Animation<double> intro;
  final bool book;

  static final _underline = Path()
    ..moveTo(2, 8)
    ..quadraticBezierTo(48, 1, 121, 6)
    ..moveTo(22, 9)
    ..quadraticBezierTo(55, 6, 82, 9);

  static final _book = Path()
    ..moveTo(12, 59)
    ..quadraticBezierTo(31, 48, 56, 62)
    ..quadraticBezierTo(76, 49, 96, 55)
    ..lineTo(90, 29)
    ..quadraticBezierTo(71, 21, 55, 37)
    ..quadraticBezierTo(33, 22, 17, 33)
    ..close()
    ..moveTo(55, 37)
    ..quadraticBezierTo(54, 49, 56, 62)
    ..moveTo(23, 39)
    ..quadraticBezierTo(33, 34, 47, 42)
    ..moveTo(20, 47)
    ..quadraticBezierTo(32, 42, 47, 50)
    ..moveTo(10, 64)
    ..quadraticBezierTo(33, 54, 56, 67)
    ..quadraticBezierTo(76, 54, 99, 60);

  static final _page = Path()
    ..moveTo(56, 38)
    ..cubicTo(64, 33, 75, 24, 72, 10)
    ..quadraticBezierTo(84, 11, 88, 24)
    ..moveTo(18, 17)
    ..lineTo(12, 12)
    ..lineTo(9, 18)
    ..lineTo(3, 12)
    ..moveTo(95, 14)
    ..lineTo(103, 10)
    ..moveTo(97, 20)
    ..lineTo(105, 19);

  void _trace(Canvas canvas, Path path, Paint ink, double amount) {
    if (amount == 1) {
      canvas.drawPath(path, ink);
      return;
    }
    final strokes = path.computeMetrics().toList();
    var remaining =
        strokes.fold(0.0, (length, stroke) => length + stroke.length) * amount;
    for (final stroke in strokes) {
      if (remaining <= 0) break;
      canvas.drawPath(
        stroke.extractPath(0, math.min(remaining, stroke.length)),
        ink,
      );
      remaining -= stroke.length;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final progress = HouseStyle.marginSketch.transform(intro.value);
    if (progress <= 0) return;
    final ink = Paint()
      ..color = book ? HouseStyle.pen : HouseStyle.binder
      ..strokeWidth = book ? 1.55 : 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (book) {
      _trace(canvas, _book, ink, const Interval(0, 0.70).transform(progress));
      _trace(canvas, _page, ink, const Interval(0.62, 1).transform(progress));
    } else {
      _trace(
        canvas,
        _underline,
        ink,
        const Interval(0, 0.40).transform(progress),
      );
    }
  }

  @override
  bool shouldRepaint(_MarginSketch oldDelegate) => oldDelegate.book != book;
}
