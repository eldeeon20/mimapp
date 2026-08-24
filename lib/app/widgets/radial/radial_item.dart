import 'package:flutter/material.dart';

/// Item del menú radial: modelo puro separado del layout.
class RadialMenuItem {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const RadialMenuItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });
}
