import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_step/models/alert_record.dart';
import 'package:safe_step/services/alerts_repository.dart';
import 'package:safe_step/services/contacts_repository.dart' show RepositoryFailure;
import 'package:safe_step/screens/history_screen.dart';
import 'package:safe_step/utils/app_theme.dart';

/// Stands in for Supabase so the history can be checked without a project, a
/// session, or a network.
class _FakeAlerts implements AlertsRepository {
  _FakeAlerts(this.rows);

  final List<AlertRecord> rows;

  @override
  Future<List<AlertRecord>> fetchRecent({int limit = 50}) async {
    return rows;
  }

  @override
  Future<AlertRecord?> fetchLatest() async {
    return rows.isEmpty ? null : rows.first;
  }
}

/// Always fails, the way a project that never ran schema.sql does.
class _BrokenAlerts implements AlertsRepository {
  @override
  Future<List<AlertRecord>> fetchRecent({int limit = 50}) async {
    throw const RepositoryFailure(
      'The alerts table is missing. Run supabase/schema.sql first.',
    );
  }

  @override
  Future<AlertRecord?> fetchLatest() => fetchRecent().then((r) => null);
}

AlertRecord record({
  required AlertReason reason,
  required Duration ago,
  String? safeSpace,
  int recipients = 2,
  int delivered = 2,
  bool located = true,
  String? failure,
  String message = 'SafeStep ALERT\nEjay needs help.',
}) {
  return AlertRecord(
    id: '${reason.wire}-${ago.inMinutes}',
    reason: reason,
    message: message,
    recipients: recipients,
    delivered: delivered,
    latitude: located ? 14.60512 : null,
    longitude: located ? 120.98423 : null,
    safeSpace: safeSpace,
    failure: failure,
    createdAt: DateTime.now().subtract(ago),
  );
}

Future<void> pump(WidgetTester tester, AlertsRepository repository) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: HistoryScreen(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an account with no alerts is told so, not shown a blank page',
      (tester) async {
    await pump(tester, _FakeAlerts(const []));

    expect(find.text('No alerts yet'), findsOneWidget);
    expect(find.textContaining('is listed here'), findsOneWidget);
  });

  testWidgets('a missing table explains itself and offers a retry',
      (tester) async {
    await pump(tester, _BrokenAlerts());

    expect(find.text('Could not load history'), findsOneWidget);
    expect(find.textContaining('Run supabase/schema.sql'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('every kind of alert is labelled for what it was',
      (tester) async {
    await pump(
      tester,
      _FakeAlerts([
        record(reason: AlertReason.panic, ago: const Duration(minutes: 5)),
        record(
          reason: AlertReason.timerExpired,
          ago: const Duration(minutes: 40),
        ),
        record(
          reason: AlertReason.leftSafeSpace,
          ago: const Duration(hours: 2),
          safeSpace: 'Home',
        ),
        record(reason: AlertReason.allClear, ago: const Duration(hours: 3)),
      ]),
    );

    expect(find.text('Panic button'), findsOneWidget);
    expect(find.text('Timer expired'), findsOneWidget);
    expect(find.text('Left "Home"'), findsOneWidget);
    expect(find.text('All clear'), findsOneWidget);
  });

  testWidgets('a send that reached nobody is not dressed up as a success',
      (tester) async {
    await pump(
      tester,
      _FakeAlerts([
        record(
          reason: AlertReason.panic,
          ago: const Duration(minutes: 5),
          delivered: 0,
        ),
      ]),
    );

    expect(find.text('Not delivered'), findsOneWidget);
    expect(find.textContaining('of 2 sent'), findsNothing);
  });

  testWidgets('an alert sent without a fix says the location is missing',
      (tester) async {
    await pump(
      tester,
      _FakeAlerts([
        record(
          reason: AlertReason.panic,
          ago: const Duration(minutes: 5),
          located: false,
        ),
      ]),
    );

    expect(find.text('No location'), findsOneWidget);
    expect(find.text('Location shared'), findsNothing);
  });

  testWidgets('the summary counts emergencies but not all-clears',
      (tester) async {
    await pump(
      tester,
      _FakeAlerts([
        record(reason: AlertReason.allClear, ago: const Duration(minutes: 1)),
        record(reason: AlertReason.panic, ago: const Duration(minutes: 5)),
      ]),
    );

    expect(find.textContaining('1 alert sent'), findsOneWidget);
  });

  testWidgets('tapping an entry shows the exact message that was sent',
      (tester) async {
    await pump(
      tester,
      _FakeAlerts([
        record(
          reason: AlertReason.panic,
          ago: const Duration(minutes: 5),
          message: 'SafeStep ALERT\nEjay needs help.\nReason: Panic button '
              'pressed\nLocation: https://maps.google.com/?q=14.60512,120.98423',
        ),
      ]),
    );

    await tester.tap(find.text('Panic button'));
    await tester.pumpAndSettle();

    expect(find.text('MESSAGE SENT'), findsOneWidget);
    expect(find.textContaining('Ejay needs help.'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Copy map link'), findsOneWidget);
  });

  testWidgets('a failed send shows what the network said', (tester) async {
    await pump(
      tester,
      _FakeAlerts([
        record(
          reason: AlertReason.panic,
          ago: const Duration(minutes: 2),
          delivered: 0,
          failure: 'The network rejected the message - check your load.',
        ),
      ]),
    );

    expect(find.text('Not delivered'), findsOneWidget);
    expect(find.textContaining('check your load'), findsOneWidget);
  });

  testWidgets('an alert with no location offers no map link', (tester) async {
    await pump(
      tester,
      _FakeAlerts([
        record(
          reason: AlertReason.panic,
          ago: const Duration(minutes: 5),
          located: false,
        ),
      ]),
    );

    await tester.tap(find.text('Panic button'));
    await tester.pumpAndSettle();

    expect(find.text('MESSAGE SENT'), findsOneWidget);
    expect(find.text('Copy map link'), findsNothing);
  });
}
