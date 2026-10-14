import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safe_step/services/timer_session_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TimerSessionRepository', () {
    test('a fresh install has no session', () async {
      final session = await TimerSessionRepository().load();

      expect(session.status, TimerSessionStatus.inactive);
      expect(session.deadline, isNull);
      expect(session.handledForDeadline, isFalse);
    });

    test('a saved session is read back exactly', () async {
      final repository = TimerSessionRepository();
      final deadline = DateTime(2026, 1, 1, 12, 30);

      await repository.save(
        TimerSession(
          status: TimerSessionStatus.running,
          deadline: deadline,
          selectedMinutes: 20,
        ),
      );

      final loaded = await repository.load();
      expect(loaded.status, TimerSessionStatus.running);
      expect(loaded.deadline, deadline);
      expect(loaded.selectedMinutes, 20);
      expect(loaded.handledForDeadline, isFalse);
    });

    test('survives a simulated process restart', () async {
      final firstProcess = TimerSessionRepository();
      await firstProcess.save(
        TimerSession(
          status: TimerSessionStatus.awaitingCheckIn,
          deadline: DateTime.now().add(const Duration(minutes: 5)),
          selectedMinutes: 30,
        ),
      );

      // A new repository instance, as a freshly restarted process would
      // create, with no shared Dart state with the one above - only
      // SharedPreferences' mocked disk persists across this boundary.
      final afterRestart = await TimerSessionRepository().load();

      expect(afterRestart.status, TimerSessionStatus.awaitingCheckIn);
      expect(afterRestart.selectedMinutes, 30);
    });

    test('clearing removes every field', () async {
      final repository = TimerSessionRepository();
      await repository.save(
        TimerSession(
          status: TimerSessionStatus.running,
          deadline: DateTime.now(),
          selectedMinutes: 10,
          handledForDeadline: true,
        ),
      );

      await repository.clear();
      final loaded = await repository.load();

      expect(loaded.status, TimerSessionStatus.inactive);
      expect(loaded.deadline, isNull);
      expect(loaded.handledForDeadline, isFalse);
    });

    test('the handledForDeadline guard survives recovery', () async {
      final repository = TimerSessionRepository();
      final pastDeadline = DateTime.now().subtract(const Duration(minutes: 1));

      await repository.save(
        TimerSession(
          status: TimerSessionStatus.expired,
          deadline: pastDeadline,
          handledForDeadline: true,
        ),
      );

      final recovered = await TimerSessionRepository().load();
      expect(recovered.isPastDeadline, isTrue);
      expect(recovered.handledForDeadline, isTrue);
    });
  });

  group('TimerSession', () {
    test('isPastDeadline is false with no deadline set', () {
      expect(TimerSession.inactive.isPastDeadline, isFalse);
    });

    test('isPastDeadline flips the moment the deadline passes', () {
      final almostNow = DateTime.now().add(const Duration(milliseconds: 50));
      final session = TimerSession(
        status: TimerSessionStatus.running,
        deadline: almostNow,
      );

      expect(session.isPastDeadline, isFalse);
      expect(
        session.remainingAt(almostNow.subtract(const Duration(milliseconds: 10))),
        greaterThan(Duration.zero),
      );
      expect(session.remainingAt(almostNow), Duration.zero);
      expect(
        session.remainingAt(almostNow.add(const Duration(seconds: 1))),
        Duration.zero,
      );
    });

    test('copyWith clearDeadline drops the deadline without touching status', () {
      final session = TimerSession(
        status: TimerSessionStatus.paused,
        deadline: DateTime.now(),
        selectedMinutes: 10,
      );

      final cleared = session.copyWith(clearDeadline: true);
      expect(cleared.deadline, isNull);
      expect(cleared.status, TimerSessionStatus.paused);
      expect(cleared.selectedMinutes, 10);
    });
  });
}
