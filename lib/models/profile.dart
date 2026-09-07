/// The account details collected on the registration form.
class Profile {
  const Profile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      phone: map['phone'] as String,
    );
  }

  final String id;
  final String firstName;
  final String lastName;
  final String phone;

  String get fullName => '$firstName $lastName';
}
