import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_styles.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController(text: 'user@example.com');
  final passwordController = TextEditingController(text: '••••••••');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.security_rounded, color: AppColors.panicPrimary),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SafeStep', style: AppStyles.titleStyle),
                          SizedBox(height: 2),
                          Text(
                            'Reliable emergency support, made simple.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Welcome back',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sign in to manage your safety network and emergency plan.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: AppStyles.cardDecoration,
                child: Column(
                  children: [
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/home');
                      },
                      child: const Text('Sign In / Register'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Need help getting started?'),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
