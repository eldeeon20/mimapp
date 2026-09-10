import 'package:flutter/material.dart';

/// Tarjeta superior del home (COLAB / CIFRAR ARCHIVOS).
class TopCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  const TopCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 210,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF071027).withValues(alpha: .90),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: iconColor.withValues(alpha: .55),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: iconColor.withValues(alpha: .12),
              blurRadius: 25,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: .20),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(icon, size: 38, color: iconColor),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
