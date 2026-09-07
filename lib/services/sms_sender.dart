import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// What the radio reported back for one message.
///
/// The point of this class is that [ok] is earned. The SMS plugin the app used
/// before reported success for anything Android accepted for queueing, so a
/// message the carrier rejected - no credit, no service, the wrong SIM - looked
/// exactly like one that arrived, and the user was told help was on the way.
class SmsResult {
  const SmsResult({
    required this.ok,
    required this.code,
    this.parts = 1,
    this.timedOut = false,
    this.error,
  });

  const SmsResult.failure(this.error)
      : ok = false,
        code = -2,
        parts = 0,
        timedOut = false;

  final bool ok;

  /// The Android result code: 0 on success, -1 when nothing answered in time,
  /// -2 when the send threw before anything was queued.
  final int code;

  final int parts;
  final bool timedOut;

  /// Set when the platform call itself failed.
  final String? error;

  /// Why it failed, in words the user can act on.
  ///
  /// Android's codes are terse and some are indistinguishable from each other
  /// in practice - a prepaid SIM out of credit usually comes back as the
  /// generic failure - so the wording names the likely cause rather than the
  /// constant.
  String get reason {
    if (ok) return 'Sent';

    switch (code) {
      case 1:
        return 'The network rejected the message. This is what an empty '
            'prepaid balance looks like - check your load.';
      case 2:
        return 'The radio is off. Turn off airplane mode.';
      case 3:
        return 'The message could not be built.';
      case 4:
        return 'No mobile service. The phone cannot reach a network.';
      case 5:
        return 'Too many messages sent at once. Wait a moment.';
      case 6:
        return 'The number is blocked by the SIM (fixed dialling is on).';
      case 9:
        return 'The radio is not available yet.';
      case 10:
        return 'The network refused the message.';
      case -1:
        return 'The network never confirmed the message. It may still be '
            'queued, but nothing came back.';
      case -2:
        return error ?? 'The message could not be sent.';
      default:
        return 'The network refused the message (code $code). On a prepaid '
            'SIM this is usually no load.';
    }
  }
}

/// One SIM that could send.
class SimCard {
  const SimCard({
    required this.subscriptionId,
    required this.label,
    required this.slot,
  });

  factory SimCard.fromMap(Map<Object?, Object?> map) {
    return SimCard(
      subscriptionId: (map['subscriptionId'] as num?)?.toInt() ?? -1,
      label: map['label'] as String? ?? 'SIM',
      slot: (map['slot'] as num?)?.toInt() ?? 0,
    );
  }

  final int subscriptionId;
  final String label;
  final int slot;
}

/// Sends SMS through the app's own Android channel, which - unlike the plugin -
/// passes a real sentIntent and so can tell a delivered message from a refused
/// one.
class SmsSender {
  const SmsSender({MethodChannel channel = _defaultChannel})
      : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel('safestep/sms');

  final MethodChannel _channel;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Sends one message. Never throws: every failure comes back as a result the
  /// caller can report.
  ///
  /// [subscriptionId] of -1 uses the phone's default SMS SIM.
  Future<SmsResult> send({
    required String address,
    required String message,
    int subscriptionId = -1,
  }) async {
    if (!isSupported) {
      return const SmsResult.failure('SMS is only available on Android.');
    }

    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'sendSms',
        {
          'address': address,
          'message': message,
          'subscriptionId': subscriptionId,
        },
      );

      if (reply == null) {
        return const SmsResult.failure('The phone gave no answer.');
      }

      return SmsResult(
        ok: reply['ok'] as bool? ?? false,
        code: (reply['code'] as num?)?.toInt() ?? -2,
        parts: (reply['parts'] as num?)?.toInt() ?? 1,
        timedOut: reply['timedOut'] as bool? ?? false,
      );
    } on PlatformException catch (error) {
      return SmsResult.failure(error.message ?? error.code);
    } on MissingPluginException {
      return const SmsResult.failure(
        'This build cannot send SMS. Reinstall the latest APK.',
      );
    } catch (error) {
      return SmsResult.failure(error.toString());
    }
  }

  /// The SIMs that could send. Empty means "the phone will pick".
  Future<List<SimCard>> availableSims() async {
    if (!isSupported) return const [];

    try {
      final rows = await _channel.invokeListMethod<Object?>('describeSims');
      if (rows == null) return const [];

      return rows
          .whereType<Map<Object?, Object?>>()
          .map(SimCard.fromMap)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
