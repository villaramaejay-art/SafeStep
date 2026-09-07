/// The fixed set of relationships a user can pick for a contact.
///
/// [wire] must match the `relationship` CHECK constraint in supabase/schema.sql.
enum ContactRelationship {
  father('father', 'Father'),
  mother('mother', 'Mother'),
  sister('sister', 'Sister'),
  spouse('spouse', 'Spouse'),
  friend('friend', 'Friend'),
  partner('partner', 'Partner');

  const ContactRelationship(this.wire, this.label);

  final String wire;
  final String label;

  static ContactRelationship fromWire(String value) {
    return ContactRelationship.values.firstWhere(
      (relationship) => relationship.wire == value,
      orElse: () => ContactRelationship.friend,
    );
  }
}

/// How urgently a contact is reached during an emergency.
enum ContactPriority {
  primary('primary', 'Primary'),
  secondary('secondary', 'Secondary');

  const ContactPriority(this.wire, this.label);

  final String wire;
  final String label;

  static ContactPriority fromWire(String value) {
    return value == primary.wire ? primary : secondary;
  }
}

class Contact {
  const Contact({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.relationship,
    required this.priority,
  });

  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      id: map['id'] as String,
      fullName: map['full_name'] as String,
      phone: map['phone'] as String,
      relationship: ContactRelationship.fromWire(map['relationship'] as String),
      priority: ContactPriority.fromWire(map['priority'] as String),
    );
  }

  final String id;
  final String fullName;
  final String phone;
  final ContactRelationship relationship;
  final ContactPriority priority;

  bool get isPrimary => priority == ContactPriority.primary;

  /// Column values for insert/update. `id` and `user_id` are handled by the
  /// repository, which owns the authenticated session.
  Map<String, dynamic> toInsert() {
    return {
      'full_name': fullName,
      'phone': phone,
      'relationship': relationship.wire,
      'priority': priority.wire,
    };
  }

  Contact copyWith({
    String? fullName,
    String? phone,
    ContactRelationship? relationship,
    ContactPriority? priority,
  }) {
    return Contact(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      relationship: relationship ?? this.relationship,
      priority: priority ?? this.priority,
    );
  }
}
