import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/alert_record.dart';
import 'contacts_repository.dart' show RepositoryFailure;

/// The `alerts` table: one row per SMS attempt, newest first.
///
/// Row level security scopes every query to the signed-in user, so the history
/// stays private without any filter on `user_id`.
class AlertsRepository {
  AlertsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const String _table = 'alerts';
  static const int defaultLimit = 50;

  final SupabaseClient _client;

  Future<List<AlertRecord>> fetchRecent({int limit = defaultLimit}) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      return rows.map(AlertRecord.fromMap).toList();
    } on PostgrestException catch (error) {
      throw RepositoryFailure(_readable(error));
    }
  }

  /// The most recent row, which is what decides whether an all-clear is still
  /// owed to the contacts.
  Future<AlertRecord?> fetchLatest() async {
    final rows = await fetchRecent(limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  String _readable(PostgrestException error) {
    // PostgREST reports a missing table as PGRST205 and only surfaces the
    // Postgres 42P01 when the request reaches the database, so both mean the
    // schema was never applied.
    if (error.code == '42P01' || error.code == 'PGRST205') {
      return 'The alerts table is missing. Run supabase/schema.sql first.';
    }
    return error.message;
  }
}
