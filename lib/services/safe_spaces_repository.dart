import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/safe_space.dart';
import 'contacts_repository.dart' show RepositoryFailure;

/// Safe spaces stored in the `safe_spaces` table.
///
/// Row level security scopes every query to the signed-in user. An account
/// starts with none: every zone is one the user chose and saved.
class SafeSpacesRepository {
  SafeSpacesRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const String _table = 'safe_spaces';

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RepositoryFailure('You need to sign in again.');
    }
    return id;
  }

  Future<List<SafeSpace>> fetchAll() async {
    try {
      final rows =
          await _client.from(_table).select().order('created_at', ascending: true);

      return rows.map(SafeSpace.fromMap).toList();
    } on PostgrestException catch (error) {
      throw RepositoryFailure(_readable(error));
    }
  }

  Future<SafeSpace> add(SafeSpace space) async {
    try {
      final row = await _client
          .from(_table)
          .insert({...space.toInsert(), 'user_id': _userId})
          .select()
          .single();

      return SafeSpace.fromMap(row);
    } on PostgrestException catch (error) {
      throw RepositoryFailure(_readable(error));
    }
  }

  /// A unique index on (user_id, lower(name)) enforces the name rule, so a
  /// clash comes back as 23505 and is turned into something readable by
  /// [_readable] rather than surfacing as a Postgres error.
  Future<void> rename(String id, String name) async {
    try {
      await _client.from(_table).update({'name': name.trim()}).eq('id', id);
    } on PostgrestException catch (error) {
      throw RepositoryFailure(_readable(error));
    }
  }

  Future<void> updateRadius(String id, double radiusKm) async {
    try {
      await _client.from(_table).update({'radius_km': radiusKm}).eq('id', id);
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
    if (error.code == '23505') {
      return 'You already have a safe space with that name.';
    }
    // PostgREST reports a missing table as PGRST205 and only surfaces the
    // Postgres 42P01 when the request reaches the database, so both mean the
    // schema was never applied.
    if (error.code == '42P01' || error.code == 'PGRST205') {
      return 'The safe_spaces table is missing. Run supabase/schema.sql first.';
    }
    return error.message;
  }
}
