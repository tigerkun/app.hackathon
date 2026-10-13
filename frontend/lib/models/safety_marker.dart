import 'package:flutter/material.dart';

class SafetyMarker {
  final Offset position;
  final IconData icon;
  final Color color;
  final String label;

  const SafetyMarker({
    required this.position,
    required this.icon,
    required this.color,
    required this.label,
  });
}
