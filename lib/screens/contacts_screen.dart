import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../services/contacts_repository.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';
import '../utils/text_format.dart';
import '../widgets/status_view.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ContactsRepository _repository = ContactsRepository();

  List<Contact> _contacts = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final contacts = await _repository.fetchAll();
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } on RepositoryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadError = failure.message;
        _isLoading = false;
      });
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Runs a write, then refreshes from the database so the UI always reflects
  /// what was actually stored - including the trigger that demotes the old
  /// primary contact.
  Future<void> _mutate(Future<void> Function() write, String success) async {
    try {
      await write();
      await _load();
      _notify(success);
    } on RepositoryFailure catch (failure) {
      _notify(failure.message);
    }
  }

  Future<void> _showContactForm({Contact? existing}) async {
    final result = await showDialog<_ContactDraft>(
      context: context,
      builder: (_) => _ContactFormDialog(existing: existing),
    );

    if (result == null || !mounted) return;

    // The database generates ids, so a new contact carries an empty one.
    final contact = Contact(
      id: existing?.id ?? '',
      fullName: result.fullName,
      phone: result.phone,
      relationship: result.relationship,
      priority: result.priority,
    );

    await _mutate(
      () => existing == null
          ? _repository.add(contact)
          : _repository.update(contact),
      existing == null
          ? '${result.fullName} added to your emergency contacts.'
          : '${result.fullName} updated.',
    );
  }

  Future<void> _setPrimary(Contact contact) {
    return _mutate(
      () => _repository.setPrimary(contact.id),
      '${contact.fullName} is now your primary contact.',
    );
  }

  Future<void> _confirmDelete(Contact contact) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text(
          '${contact.fullName} will no longer be alerted during an emergency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    await _mutate(
      () => _repository.delete(contact.id),
      '${contact.fullName} removed.',
    );
  }

  // --- Widgets --------------------------------------------------------------

  Widget _buildSummary() {
    final primaryCount = _contacts.where((c) => c.isPrimary).length;

    final String detail;
    final IconData icon;
    final Color tone;

    if (_loadError != null) {
      icon = Icons.cloud_off_rounded;
      tone = AppColors.danger;
      detail = 'Could not reach your saved contacts.';
    } else if (_isLoading) {
      icon = Icons.cloud_sync_rounded;
      tone = AppColors.textTertiary;
      detail = 'Loading your emergency contacts...';
    } else if (_contacts.isEmpty) {
      icon = Icons.emergency_rounded;
      tone = AppColors.primary;
      detail = 'Add the people who should be alerted during an emergency.';
    } else if (primaryCount == 0) {
      icon = Icons.star_outline_rounded;
      tone = AppColors.warning;
      detail = '${TextFormat.count(_contacts.length, 'contact')} saved. '
          'Set one as primary so they are alerted first.';
    } else {
      icon = Icons.verified_user_rounded;
      tone = AppColors.success;
      detail = '${TextFormat.count(_contacts.length, 'contact')} saved. '
          'Your primary contact is alerted first.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppStyles.tintedDecoration,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppSpacing.medium,
            ),
            child: Icon(icon, color: tone, size: 20),
          ),
          AppSpacing.hGapMd,
          Expanded(child: Text(detail, style: AppStyles.captionStyle)),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge(Contact contact) {
    final isPrimary = contact.isPrimary;
    final color = isPrimary ? AppColors.primary : AppColors.textTertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: AppStyles.pillDecoration(color),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPrimary ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            contact.priority.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(Contact contact) {
    final initials = contact.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
        .join();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppStyles.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: contact.isPrimary
                    ? [AppColors.primarySoft, AppColors.primary]
                    : [AppColors.surfaceVariant, AppColors.surfaceVariant],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(
                color: contact.isPrimary ? Colors.white : AppColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        contact.fullName,
                        style: AppStyles.sectionTitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AppSpacing.hGapSm,
                    _buildPriorityBadge(contact),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      contact.relationship.label,
                      style: AppStyles.captionStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '  ·  ${contact.phone}',
                      style: AppStyles.captionStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Contact options',
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'primary':
                  _setPrimary(contact);
                case 'edit':
                  _showContactForm(existing: contact);
                case 'delete':
                  _confirmDelete(contact);
              }
            },
            itemBuilder: (context) => [
              if (!contact.isPrimary)
                const PopupMenuItem(
                  value: 'primary',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.star_rounded, size: 20),
                    title: Text('Set as primary'),
                  ),
                ),
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_rounded, size: 20),
                  title: Text('Edit'),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.danger,
                  ),
                  title: Text(
                    'Remove',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const StatusView.loading(message: 'Loading your contacts...');
    }

    if (_loadError != null) {
      return StatusView(
        icon: Icons.cloud_off_rounded,
        tone: AppColors.danger,
        title: 'Could not load your contacts',
        message: _loadError!,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try again'),
        ),
      );
    }

    if (_contacts.isEmpty) {
      return StatusView(
        icon: Icons.contact_phone_outlined,
        title: 'No emergency contacts yet',
        message: 'Save someone you trust, then mark one of them as your '
            'primary contact so they are alerted first.',
        action: FilledButton.icon(
          onPressed: () => _showContactForm(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add your first contact'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        // The extra row is the backup-contact prompt, shown only when there is
        // exactly one person to alert.
        itemCount: _contacts.length + (_contacts.length == 1 ? 1 : 0),
        separatorBuilder: (_, __) => AppSpacing.gapMd,
        itemBuilder: (context, index) {
          if (index < _contacts.length) {
            return _buildContactCard(_contacts[index]);
          }
          return _buildBackupPrompt();
        },
      ),
    );
  }

  /// Shown when there is exactly one contact.
  ///
  /// One contact is one phone that has to be switched on, in signal, and
  /// answered. The screen has room to say so, and saying it is more use than
  /// leaving the space empty.
  Widget _buildBackupPrompt() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppStyles.statusDecoration(AppColors.warning),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.group_add_rounded,
            size: 20,
            color: AppColors.warning,
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add a second contact',
                  style: AppStyles.labelStyle.copyWith(
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'If your only contact has their phone off or out of signal, '
                  'nobody hears the alert.',
                  style: AppStyles.captionStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Emergency Contacts'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh contacts',
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.page,
          child: Column(
            children: [
              _buildSummary(),
              AppSpacing.gapLg,
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
      floatingActionButton: _contacts.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _isLoading ? null : () => _showContactForm(),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Contact',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
    );
  }
}

/// Values collected by [_ContactFormDialog].
class _ContactDraft {
  const _ContactDraft({
    required this.fullName,
    required this.phone,
    required this.relationship,
    required this.priority,
  });

  final String fullName;
  final String phone;
  final ContactRelationship relationship;
  final ContactPriority priority;
}

/// Collects full name, contact number, relationship and priority.
///
/// A widget rather than a closure so the controllers are disposed with the
/// route instead of while its exit animation is still rebuilding the fields.
class _ContactFormDialog extends StatefulWidget {
  const _ContactFormDialog({this.existing});

  final Contact? existing;

  @override
  State<_ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<_ContactFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late ContactRelationship? _relationship;
  late ContactPriority _priority;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.fullName ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _relationship = existing?.relationship;
    _priority = existing?.priority ?? ContactPriority.secondary;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter the full name.';
    if (name.length < 2) return 'Name looks too short.';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return 'Enter a contact number.';

    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return 'Enter at least 7 digits.';
    if (!RegExp(r'^\+?[0-9()\s-]+$').hasMatch(phone)) {
      return 'Use digits, spaces, dashes or a leading +.';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    Navigator.of(context).pop(
      _ContactDraft(
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        relationship: _relationship!,
        priority: _priority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit contact' : 'Add emergency contact'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            // Without this, an error stays on screen after the user has already
            // fixed the field, until the next Save press re-runs validation.
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: !isEditing,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: _validateName,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    hintText: 'Maya Dela Cruz',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                ),
                AppSpacing.gapLg,
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: _validatePhone,
                  decoration: const InputDecoration(
                    labelText: 'Contact number',
                    hintText: '+63 917 123 4567',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                ),
                AppSpacing.gapLg,
                DropdownButtonFormField<ContactRelationship>(
                  initialValue: _relationship,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Relationship',
                    prefixIcon: Icon(Icons.diversity_3_outlined, size: 20),
                  ),
                  hint: const Text('Select a relationship'),
                  validator: (value) =>
                      value == null ? 'Select a relationship.' : null,
                  items: [
                    for (final relationship in ContactRelationship.values)
                      DropdownMenuItem(
                        value: relationship,
                        child: Text(relationship.label),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _relationship = value);
                  },
                ),
                AppSpacing.gapXl,
                const Text('PRIORITY', style: AppStyles.overlineStyle),
                AppSpacing.gapSm,
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ContactPriority>(
                    segments: const [
                      ButtonSegment(
                        value: ContactPriority.primary,
                        label: Text('Primary'),
                        icon: Icon(Icons.star_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: ContactPriority.secondary,
                        label: Text('Secondary'),
                        icon: Icon(Icons.star_outline_rounded, size: 16),
                      ),
                    ],
                    selected: {_priority},
                    onSelectionChanged: (selection) {
                      setState(() => _priority = selection.first);
                    },
                  ),
                ),
                AppSpacing.gapSm,
                Text(
                  _priority == ContactPriority.primary
                      ? 'Alerted first. Any other primary contact becomes '
                          'secondary.'
                      : 'Alerted after your primary contact.',
                  style: AppStyles.captionStyle,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Save' : 'Add contact'),
        ),
      ],
    );
  }
}
