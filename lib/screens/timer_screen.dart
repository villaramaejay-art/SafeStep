import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_styles.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  int selectedMinutes = 30;
  bool isRunning = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Timer')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: AppStyles.cardDecoration,
                child: Column(
                  children: [
                    const Text('Dead Man\'s Switch', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text(
                      'If no activity is detected, the app will alert your contacts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: 0.7,
                            strokeWidth: 14,
                            backgroundColor: AppColors.border,
                            valueColor: const AlwaysStoppedAnimation(AppColors.panicPrimary),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$selectedMinutes', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
                              const Text('min', style: TextStyle(color: AppColors.textSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      children: [30, 60, 90].map((minutes) {
                        final selected = minutes == selectedMinutes;
                        return ChoiceChip(
                          label: Text('${minutes}m'),
                          selected: selected,
                          onSelected: (_) => setState(() => selectedMinutes = minutes),
                          selectedColor: AppColors.panicPrimary,
                          labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => setState(() => isRunning = !isRunning),
                      child: Text(isRunning ? 'Cancel Timer' : 'Start Timer'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
