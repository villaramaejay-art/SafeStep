import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../utils/app_colors.dart';
import '../utils/app_styles.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  final List<Contact> contacts = const [
    Contact(id: '1', name: 'Maya', relationship: 'Sister', phone: '+1 555 1010', isPrimary: true),
    Contact(id: '2', name: 'Daniel', relationship: 'Friend', phone: '+1 555 2020', isPrimary: false),
    Contact(id: '3', name: 'Rosa', relationship: 'Roommate', phone: '+1 555 3030', isPrimary: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AppStyles.cardDecoration.copyWith(
                  color: AppColors.surfaceVariant,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.emergency_rounded, color: AppColors.panicPrimary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Trusted people who will be informed during an emergency.',
                        style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: contacts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppStyles.cardDecoration,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColors.panicPrimary.withValues(alpha: 0.16),
                            child: const Icon(Icons.person_rounded, color: AppColors.panicPrimary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(contact.name, style: AppStyles.sectionTitleStyle.copyWith(color: AppColors.textPrimary)),
                                    if (contact.isPrimary) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.star_rounded, color: AppColors.success, size: 18),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(contact.relationship, style: const TextStyle(color: AppColors.textSecondary)),
                                const SizedBox(height: 4),
                                Text(contact.phone, style: const TextStyle(color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('Add New Contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
