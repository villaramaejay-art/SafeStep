import 'dart:async' show TimeoutException;
import 'dart:io' show Platform;

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/alert_record.dart';
import '../models/contact.dart';
import '../models/profile.dart';
import 'auth_service.dart';
import 'contacts_repository.dart';
import 'geocoding_service.dart';
import 'location_service.dart';
import 'sms_sender.dart';
import '../utils/text_format.dart';

// AlertReason lives with the alert model, next to the history rows it labels,
// but it is re-exported here so the triggers keep importing one file.
export '../models/alert_record.dart' show AlertReason, AlertTone;

/// Why an alert could not be sent, when it could not.
enum AlertProblem {
  unsupportedPlatform,
  permissionDenied,
  noContacts,
  sendFailed,
}

/// What happened when an alert was attempted.
class AlertOutcome {
  const AlertOutcome({
    required this.message,
    required this.recipients,
    required this.delivered,
    this.reason,
    this.problem,
    this.detail,
  });

  const AlertOutcome.failed(this.problem, this.detail)
      : message = '',
        recipients = 0,
        delivered = 0,
        reason = null;

  final String message;
  final int recipients;
  final int delivered;

  /// What was sent, so the confirmation can name it. Null when nothing went out.
  final AlertReason? reason;

  final AlertProblem? problem;
  final String? detail;

  bool get isSuccess => problem == null && delivered > 0;

  /// A line that can go straight into a SnackBar.
  String get summary {
    switch (problem) {
      case AlertProblem.unsupportedPlatform:
        return 'SMS alerts only work on Android. Nothing was sent.';
      case AlertProblem.permissionDenied:
        // Android stops showing the dialog after two refusals, so naming the
        // Settings path is the only way back for a user who already said no.
        return 'SMS permission is off. Turn it on in Settings > Apps > '
            'SafeStep > Permissions > SMS.';
      case AlertProblem.noContacts:
        return 'Add an emergency contact first - there was nobody to alert.';
      case AlertProblem.sendFailed:
        return detail ?? 'Could not send the alert.';
      case null:
        // Named for what actually went out, so the confirmation does not call
        // a location update an alert either.
        final what = switch (reason?.tone) {
          AlertTone.standDown => 'All-clear',
          AlertTone.notice => 'Update',
          _ => 'Alert',
        };
        return delivered == recipients
            ? '$what sent to ${TextFormat.count(delivered, 'contact')}.'
            : '$what sent to $delivered of '
                '${TextFormat.count(recipients, 'contact')}.';
    }
  }
}

/// Renders a position for the SMS body.
///
/// [linked] false drops the URL and leaves bare coordinates. Philippine
/// carriers block person-to-person SMS containing links as an anti-smishing
/// measure and reject them with a plain "generic failure", so on those networks
/// the linked version never arrives and the unlinked one does. A recipient can
/// paste coordinates into any map app; a message that was refused helps nobody.
String formatLocationLine(
  LatLng location, {
  required bool linked,
  double? accuracyMeters,
  String? placeName,
}) {
  final lat = location.latitude.toStringAsFixed(5);
  final lon = location.longitude.toStringAsFixed(5);
  final accuracy =
      accuracyMeters == null ? '' : ' (+/-${accuracyMeters.round()}m)';

  if (linked) {
    return 'Location: https://maps.google.com/?q=$lat,$lon$accuracy';
  }

  // Without a link, the street name is what someone reads and acts on; the
  // coordinates are there for whoever wants to be exact.
  if (placeName != null) {
    return 'Near: $placeName\nCoords: $lat, $lon$accuracy';
  }

  return 'Location: $lat, $lon$accuracy';
}

/// Builds the SMS body.
///
/// Kept a free function with no dependencies so the exact wording can be
/// tested without a handset, a session, or a SIM.
String buildAlertMessage({
  required AlertReason reason,
  required String senderName,
  LatLng? location,
  double? accuracyMeters,
  DateTime? at,
  bool linkedMap = true,
  String? placeName,
}) {
  assert(
    reason.isEmergency,
    'Only an emergency says someone needs help. Use buildNoticeMessage for a '
    'safe space exit, or buildAllClearMessage to stand an alert down.',
  );

  final when = at ?? DateTime.now();
  final buffer = StringBuffer('SafeStep ALERT\n');

  buffer.writeln('$senderName needs help.');
  buffer.writeln('Reason: ${reason.description}');

  if (location == null) {
    buffer.writeln('Location: unavailable');
  } else {
    buffer.writeln(
      formatLocationLine(
        location,
        linked: linkedMap,
        accuracyMeters: accuracyMeters,
        placeName: placeName,
      ),
    );
  }

  buffer.write('Time: ${formatAlertTimestamp(when)}');

  return buffer.toString();
}

/// Strips a saved phone number down to what the radio accepts.
///
/// Contacts are typed by hand, so they arrive as "0932 292 0323" or
/// "(0932) 292-0323". Spaces and punctuation make the send fail, and it fails
/// the same silent way an over-long message does, so they are removed here.
/// A leading `+` is the one non-digit that survives, because it carries the
/// country code.
String smsAddress(String phone) {
  final trimmed = phone.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

  return trimmed.startsWith('+') ? '+$digits' : digits;
}

/// Builds the SMS for leaving a safe space.
///
/// Deliberately not an alert. Walking out of a zone is a fact about where
/// somebody is, not a request for help, and a contact who is told "needs help"
/// every time the user goes to the shop will stop reading the ones that mean
/// it. The header says UPDATE so it can be told apart at a glance in an inbox.
String buildNoticeMessage({
  required String senderName,
  required String safeSpaceName,
  LatLng? location,
  double? accuracyMeters,
  DateTime? at,
  bool linkedMap = true,
  String? placeName,
}) {
  final when = at ?? DateTime.now();
  final buffer = StringBuffer('SafeStep UPDATE\n');

  buffer.writeln('$senderName left "$safeSpaceName".');

  if (location != null) {
    buffer.writeln(
      formatLocationLine(
        location,
        linked: linkedMap,
        accuracyMeters: accuracyMeters,
        placeName: placeName,
      ),
    );
  }

  buffer.write('Time: ${formatAlertTimestamp(when)}');

  return buffer.toString();
}

/// Builds the stand-down SMS.
///
/// It has to arrive on the same channel as the alarm: a contact who got the
/// alert by SMS should not have to guess whether silence means safe.
String buildAllClearMessage({
  required String senderName,
  LatLng? location,
  DateTime? at,
  bool linkedMap = true,
  String? placeName,
}) {
  final when = at ?? DateTime.now();
  final buffer = StringBuffer('SafeStep ALL CLEAR\n');

  buffer.writeln('$senderName is safe.');
  // Deliberately terse: this wording keeps the whole message inside a single
  // 160-character SMS for a typical name, so standing an alert down costs one
  // message rather than two.
  buffer.writeln('Earlier SafeStep alert stood down.');

  if (location != null) {
    buffer.writeln(
      formatLocationLine(location, linked: linkedMap, placeName: placeName),
    );
  }

  buffer.write('Time: ${formatAlertTimestamp(when)}');

  return buffer.toString();
}

/// Sends emergency SMS from the handset and records what went out in the
/// `alerts` table.
///
/// The send itself goes through [SmsSender], the app's own channel, so a
/// message the network refused is reported as refused rather than counted as
/// delivered. `another_telephony` is kept only for the permission prompt.
///
/// Android only: no mobile platform other than Android lets an app send an SMS
/// without the user pressing send, so every other platform reports
/// [AlertProblem.unsupportedPlatform] instead of failing silently.
class EmergencyService {
  EmergencyService({
    Telephony? telephony,
    SmsSender? sms,
    GeocodingService? geocoding,
    ContactsRepository? contacts,
    LocationService? location,
    AuthService? auth,
    SupabaseClient? client,
  })  : _telephony = telephony ?? Telephony.instance,
        _sms = sms ?? const SmsSender(),
        _geocoding = geocoding ?? GeocodingService(),
        _contacts = contacts ?? ContactsRepository(),
        _location = location ?? LocationService(),
        _auth = auth ?? AuthService(),
        _client = client ?? Supabase.instance.client;

  /// Guards against a stuck trigger firing the same alert over and over, which
  /// would cost the user real messages.
  static const Duration cooldown = Duration(seconds: 60);

  final Telephony _telephony;
  final SmsSender _sms;
  final GeocodingService _geocoding;
  final ContactsRepository _contacts;
  final LocationService _location;
  final AuthService _auth;
  final SupabaseClient _client;

  static final Map<AlertReason, DateTime> _lastSentAt = {};

  /// Set once this network has been observed refusing a message for its link
  /// and accepting the same message without one.
  ///
  /// Learned rather than configured: no list of carriers to keep up to date,
  /// and no assumption about where the user is. It costs one wasted send, once
  /// per app run, and saves one on every alert after that.
  static bool _carrierStripsLinks = false;

  static void resetLinkLearning() => _carrierStripsLinks = false;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// The cooldown rule on its own, so it can be tested without a handset.
  static bool isWithinCooldown(DateTime? lastSent, DateTime now) {
    if (lastSent == null) return false;
    return now.difference(lastSent) < cooldown;
  }

  /// True when [reason] fired recently enough that it should not fire again.
  static bool isCoolingDown(AlertReason reason, {DateTime? now}) {
    return isWithinCooldown(_lastSentAt[reason], now ?? DateTime.now());
  }

  static void resetCooldowns() => _lastSentAt.clear();

  Future<bool> ensurePermission() async {
    if (!isSupported) return false;

    try {
      return await _telephony.requestSmsPermissions ?? false;
    } on PlatformException {
      // A denial arrives as result.error, not as `false`. Left uncaught it
      // escapes all the way past the button handler, so the alert does nothing
      // at all and says nothing either - the exact symptom of a user who once
      // tapped "Don't allow".
      return false;
    }
  }

  /// Sends the alert to every saved contact, primary first.
  Future<AlertOutcome> sendAlert({
    required AlertReason reason,
    String? safeSpaceName,
    LocationFix? knownLocation,
  }) {
    assert(
      reason.tone != AlertTone.standDown,
      'Use sendAllClear to stand an alert down.',
    );
    return _dispatch(
      reason: reason,
      safeSpaceName: safeSpaceName,
      knownLocation: knownLocation,
    );
  }

  /// Tells the same contacts that the user is safe, closing the loop an alert
  /// opened. Goes to everyone, because there is no record of who read the
  /// original and a duplicate reassurance costs nothing.
  Future<AlertOutcome> sendAllClear({LocationFix? knownLocation}) {
    return _dispatch(
      reason: AlertReason.allClear,
      knownLocation: knownLocation,
    );
  }

  /// Wraps [_run] so the alert path can never throw into the caller.
  ///
  /// A panic button that silently does nothing is worse than one that reports a
  /// failure: the user walks away believing help is coming. Every escape route
  /// out of here is an [AlertOutcome] that says something.
  Future<AlertOutcome> _dispatch({
    required AlertReason reason,
    String? safeSpaceName,
    LocationFix? knownLocation,
  }) async {
    try {
      return await _run(
        reason: reason,
        safeSpaceName: safeSpaceName,
        knownLocation: knownLocation,
      );
    } catch (error) {
      return AlertOutcome.failed(
        AlertProblem.sendFailed,
        'The alert could not be sent: $error',
      );
    }
  }

  /// The shared path: permission, contacts, a location fix, the SMS loop, and
  /// the audit row. Only the message body differs between an alert and an
  /// all-clear.
  Future<AlertOutcome> _run({
    required AlertReason reason,
    String? safeSpaceName,
    LocationFix? knownLocation,
  }) async {
    if (!isSupported) {
      return const AlertOutcome.failed(
        AlertProblem.unsupportedPlatform,
        null,
      );
    }

    if (!await ensurePermission()) {
      return const AlertOutcome.failed(AlertProblem.permissionDenied, null);
    }

    // The one lookup an alert genuinely cannot do without: the numbers to text.
    // Capped so a dead connection fails loudly instead of hanging on a screen
    // that says "Sending".
    final List<Contact> contacts;
    try {
      contacts = await _contacts.fetchAll().timeout(
            const Duration(seconds: 10),
          );
    } on RepositoryFailure catch (failure) {
      return AlertOutcome.failed(AlertProblem.sendFailed, failure.message);
    } on TimeoutException {
      return const AlertOutcome.failed(
        AlertProblem.sendFailed,
        'Could not reach your contact list. Check your connection.',
      );
    }

    if (contacts.isEmpty) {
      return const AlertOutcome.failed(AlertProblem.noContacts, null);
    }

    // Reuse a fix the caller already has; only ask for a new one otherwise, so
    // an alert is never delayed waiting for GPS it could have had.
    final fix = knownLocation ?? await _location.getFixForAlert();

    // Started now and collected below, so the address lookup runs alongside the
    // profile read instead of adding its own seconds to the wait.
    //
    // A street name is what turns an alert into somewhere a person can go, and
    // it is the only useful location a carrier that strips links will carry.
    final placeRequest = fix == null
        ? Future<String?>.value()
        : _geocoding.describePlace(
            fix.point,
            timeout: const Duration(seconds: 4),
          );

    // SMS needs no internet, but this does. Capped so a weak connection cannot
    // hold up an alert - the message goes out under a generic name rather than
    // not at all.
    Profile? profile;
    try {
      profile = await _auth
          .fetchProfile()
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      profile = null;
    }

    final senderName = profile?.fullName ?? 'A SafeStep user';

    // Non-fatal: without it the alert still goes, with coordinates alone.
    final placeName = await placeRequest;

    String body({required bool linkedMap}) {
      switch (reason.tone) {
        case AlertTone.emergency:
          return buildAlertMessage(
            reason: reason,
            senderName: senderName,
            location: fix?.point,
            accuracyMeters: fix?.accuracy,
            linkedMap: linkedMap,
            placeName: placeName,
          );
        case AlertTone.notice:
          return buildNoticeMessage(
            senderName: senderName,
            safeSpaceName: safeSpaceName ?? 'a safe space',
            location: fix?.point,
            accuracyMeters: fix?.accuracy,
            linkedMap: linkedMap,
            placeName: placeName,
          );
        case AlertTone.standDown:
          return buildAllClearMessage(
            senderName: senderName,
            location: fix?.point,
            linkedMap: linkedMap,
            placeName: placeName,
          );
      }
    }

    final linkedBody = body(linkedMap: true);
    final plainBody = body(linkedMap: false);

    // Only worth a second attempt when the two actually differ - with no fix
    // there is no link to drop.
    final canRetryWithoutLink = fix != null;

    var message = linkedBody;
    var delivered = 0;
    String? lastError;

    // Once this network has been seen to strip links, the linked attempt is a
    // known-failing send standing between the user and help. Skipped from then
    // on, for the life of the process.
    if (_carrierStripsLinks && canRetryWithoutLink) {
      message = plainBody;
    }

    for (final contact in contacts) {
      final address = smsAddress(contact.phone);

      // Waits for the radio's own verdict rather than assuming the send worked,
      // so `delivered` counts messages the network accepted - not messages the
      // app handed over and hoped for.
      var sent = await _sms.send(address: address, message: message);

      if (!sent.ok && canRetryWithoutLink && message == linkedBody) {
        // Carriers that block links refuse the message outright, and the
        // refusal looks like any other generic failure. Rather than decide in
        // advance which networks those are, the alert simply tries again
        // without the URL: coordinates a contact can paste beat a message that
        // was never delivered.
        final retry = await _sms.send(address: address, message: plainBody);

        if (retry.ok) {
          // The link was the only difference, so the network refusing one and
          // accepting the other is as clear an answer as this ever gets.
          message = plainBody;
          _carrierStripsLinks = true;
        }
        sent = retry;
      }

      if (sent.ok) {
        delivered++;
      } else {
        lastError = sent.reason;
      }
    }

    _lastSentAt[reason] = DateTime.now();
    await _log(
      reason: reason,
      message: message,
      recipients: contacts.length,
      delivered: delivered,
      point: fix?.point,
      safeSpaceName: safeSpaceName,
      failure: delivered == contacts.length ? null : lastError,
    );

    if (delivered == 0) {
      return AlertOutcome.failed(
        AlertProblem.sendFailed,
        lastError == null
            ? 'The messages could not be sent.'
            : 'Sending failed: $lastError',
      );
    }

    return AlertOutcome(
      message: message,
      recipients: contacts.length,
      delivered: delivered,
      reason: reason,
    );
  }

  /// Best effort: a failed log must never hide a sent alert.
  Future<void> _log({
    required AlertReason reason,
    required String message,
    required int recipients,
    required int delivered,
    LatLng? point,
    String? safeSpaceName,
    String? failure,
  }) async {
    final userId = _auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client.from('alerts').insert({
        'user_id': userId,
        'reason': reason.wire,
        'message': message,
        'recipients': recipients,
        'delivered': delivered,
        'latitude': point?.latitude,
        'longitude': point?.longitude,
        'safe_space': safeSpaceName,
        'failure': failure,
      }).timeout(const Duration(seconds: 6));
    } catch (_) {
      // The SMS already went out. Losing the audit row - to a rejected insert
      // or to no connection at all - is not worth surfacing, and must never
      // hold up the confirmation the user is waiting on.
    }
  }
}
