import 'package:flutter/material.dart';

/// Shared visual tokens for the Degree Atlas house notebook.
abstract final class HouseStyle {
  static const paper = Color(0xFFFFFBF0);
  static const desk = Color(0xFFEFE7DD);
  static const ink = Color(0xFF211D1B);
  static const graphite = Color(0xFF675951);
  static const binder = Color(0xFF732F36);
  static const pen = Color(0xFF2B5078);
  static const ruling = Color(0xFFEBEEF0);
  static const margin = Color(0xFFE6C7C7);
  static const pageEdge = Color(0xFFE8DCD0);

  static const mark = 'assets/brand/degree-atlas.svg';
  static const wordmark = 'assets/brand/degree-atlas-wordmark.svg';
  static const handwriting = 'Kalam';
  static const readingWidth = 920.0;
  static const ruleSpacing = 28.0;
  static const spacing = 8.0;

  static const intro = Duration(milliseconds: 1550);
  static const titleWrite = Interval(0.04, 0.48, curve: Curves.easeOutSine);
  static const noteDrop = Interval(0.48, 0.74, curve: Curves.easeOutCubic);
  static const marginSketch = Interval(0.54, 1, curve: Curves.easeInOutSine);
  static const firstDoodle = Duration(milliseconds: 2200);
  static const doodleBurst = Duration(milliseconds: 2450);
  static const doodleInterval = Duration(seconds: 9);

  static const heading = TextStyle(
    color: ink,
    fontFamily: handwriting,
    fontWeight: FontWeight.w700,
    fontSize: 40,
    height: 1.16,
  );
  static const noteHeading = TextStyle(
    color: ink,
    fontFamily: handwriting,
    fontWeight: FontWeight.w700,
    fontSize: 25,
    height: 1.25,
  );
  static const label = TextStyle(
    color: binder,
    fontFamily: 'monospace',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.35,
  );
  static const body = TextStyle(color: ink, fontSize: 15, height: 1.55);
}
