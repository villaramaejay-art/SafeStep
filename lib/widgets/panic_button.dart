import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class PanicButton extends StatelessWidget {
  final VoidCallback onPressed;
  const PanicButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.panicPrimary,
          foregroundColor: Colors.white,
          elevation: 8,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(24),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 54),
            SizedBox(height: 8),
            Text(
              'PANIC',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1.4),
            ),
            Text('Tap now', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
