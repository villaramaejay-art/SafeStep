import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/contact.dart';

/// Raised for problems worth showing the user verbatim.
class RepositoryFailure implements Exception {
  const RepositoryFailure(this.message);

  final String message;

  @override
  String toString() => 'RepositoryFailure: $message';
}

/// Emergency contacts stored in the `contacts` table.
///
/// Row level security scopes every query to the signed-in user, so no filter
/// on `user_id` is needed when reading.
class ContactsRepository {
  ContactsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const String _table = 'contacts';

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RepositoryFailure('You need to sign in again.');
    }
    return id;
  }

  /// Primary first, then oldest to newest.
  Future<List<Contact>> fetchAll() async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .order('priority', ascending: true) // 'primary' sorts before 'secondary'
          .order('created_at', ascending: true);

      return rows.map(Contact.fromMap).toList();
    } on PostgrestException catch (error) {
      throw RepositoryFailure(_readable(error));
    }
  }

  Future<void> add(Contact contact) async {
    try {
      await _client.from(_table).insert({
        ...contact.toInsert(),
        'user_id': _userId,
      });
    } on PostgrestException catch (error) {
      throw RepositoryFailure(_readable(error));
    }
  }

  Future<void> update(Contact contact) async {
    try {
      await _client.from(_table).update(contact.toInsert()).eq('id', contact.id);
    } on PostgrestException catch (error) {
      throw RepositoryFailure(_readable(error));
    }
  }

  /// A database trigger demotes whichever contact was primary before.
  Future<void> setPrimary(String id) async {
    try {
      await _client
          .from(_table)
          .update({'priority': ContactPriority.primary.wire})
          .eq('id', id);
    } on PostgrestException catch (error) {
      throw RepositoryFailure(_readable(error));
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
    } on PostgrestException catch (error) {
      throw RepositoryFailure(_readable(error));
    }
  }

  String _readable(PostgrestException error) {
    if (error.code == '23514') {
      return 'That contact has a value the database rejected.';
    }
    // PostgREST reports a missing table as PGRST205 and only surfaces the
    // Postgres 42P01 when the request reaches the database, so both mean the
    // schema was never applied.
    if (error.code == '42P01' || error.code == 'PGRST205') {
      return 'The contacts table is missing. Run supabase/schema.sql first.';
    }
    return error.message;
  }
}
