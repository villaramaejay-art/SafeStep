package com.example.safe_step

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Sends the emergency SMS and reports what the radio actually did with it.
 *
 * The reason this exists rather than leaving the job to another_telephony: that
 * plugin passes a null sentIntent, so Android has nowhere to report a failure,
 * and the plugin's own listener broadcasts "SENT" for every message regardless
 * of the result code. A message the carrier rejected - no credit, no service,
 * wrong SIM - looked exactly like one that arrived, and the app told the user
 * help was on the way.
 *
 * Here every send carries a real sentIntent, and the result code comes back to
 * Dart so the failure can be named.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "safestep/sms"

        /** Long enough for a slow network to answer, short enough to not hang an alert. */
        private const val REPLY_TIMEOUT_MS = 30_000L
    }

    private var sendCounter = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val address = call.argument<String>("address")
                        val message = call.argument<String>("message")
                        val subscriptionId = call.argument<Int>("subscriptionId") ?: -1

                        if (address.isNullOrBlank() || message.isNullOrBlank()) {
                            result.error("bad_args", "address and message are required", null)
                        } else {
                            sendSms(address, message, subscriptionId, result)
                        }
                    }
                    "describeSims" -> result.success(describeSims())
                    else -> result.notImplemented()
                }
            }
    }

    private fun smsManagerFor(subscriptionId: Int): SmsManager {
        val base = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }

        return if (subscriptionId >= 0) {
            @Suppress("DEPRECATION")
            SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
        } else {
            base
        }
    }

    /**
     * Sends one message and replies once every part has reported back.
     *
     * The reply is whichever failure came first, or success only if every part
     * succeeded: a half-delivered alert is a failed alert.
     */
    private fun sendSms(
        address: String,
        message: String,
        subscriptionId: Int,
        result: MethodChannel.Result,
    ) {
        val smsManager: SmsManager
        val parts: ArrayList<String>

        try {
            smsManager = smsManagerFor(subscriptionId)
            parts = smsManager.divideMessage(message)
        } catch (error: Exception) {
            result.error("sms_manager", error.message ?: error.toString(), null)
            return
        }

        // Unique per send, so two alerts in flight cannot read each other's
        // results.
        val action = "com.example.safe_step.SMS_SENT.${sendCounter++}"
        val handler = Handler(Looper.getMainLooper())

        var outstanding = parts.size
        var firstFailure: Int? = null
        var replied = false

        lateinit var receiver: BroadcastReceiver
        lateinit var timeout: Runnable

        // Guarded so the timeout and the last broadcast cannot both answer.
        fun reply(ok: Boolean, code: Int, timedOut: Boolean) {
            if (replied) return
            replied = true
            handler.removeCallbacks(timeout)
            try {
                unregisterReceiver(receiver)
            } catch (_: Exception) {
                // Already gone; nothing to undo.
            }
            result.success(
                mapOf(
                    "ok" to ok,
                    "code" to code,
                    "parts" to parts.size,
                    "timedOut" to timedOut,
                )
            )
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (resultCode != Activity.RESULT_OK && firstFailure == null) {
                    firstFailure = resultCode
                }
                outstanding--
                if (outstanding <= 0) {
                    val failure = firstFailure
                    reply(failure == null, failure ?: 0, false)
                }
            }
        }

        timeout = Runnable {
            // No answer at all. Reported rather than assumed either way: the
            // message may still be queued on the radio.
            reply(false, -1, true)
        }

        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        handler.postDelayed(timeout, REPLY_TIMEOUT_MS)

        val intents = ArrayList<PendingIntent>(parts.size)
        for (i in parts.indices) {
            intents.add(
                PendingIntent.getBroadcast(
                    this,
                    i,
                    Intent(action).setPackage(packageName),
                    PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
                )
            )
        }

        try {
            if (parts.size == 1) {
                smsManager.sendTextMessage(address, null, parts[0], intents[0], null)
            } else {
                smsManager.sendMultipartTextMessage(address, null, parts, intents, null)
            }
        } catch (error: Exception) {
            // A synchronous throw means nothing was queued, so no broadcast is
            // coming and the reply has to be made here.
            if (!replied) {
                replied = true
                handler.removeCallbacks(timeout)
                try {
                    unregisterReceiver(receiver)
                } catch (_: Exception) {
                }
                result.error("send_failed", error.message ?: error.toString(), null)
            }
        }
    }

    /**
     * The SIMs that could send, so a dual-SIM phone can say which one is being
     * used - a send from a SIM with no credit fails silently otherwise.
     */
    private fun describeSims(): List<Map<String, Any?>> {
        return try {
            val manager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as? android.telephony.SubscriptionManager ?: return emptyList()

            @Suppress("MissingPermission")
            val active = manager.activeSubscriptionInfoList ?: return emptyList()

            active.map {
                mapOf(
                    "subscriptionId" to it.subscriptionId,
                    "label" to (it.displayName?.toString() ?: "SIM ${it.simSlotIndex + 1}"),
                    "slot" to it.simSlotIndex,
                )
            }
        } catch (_: Exception) {
            // Reading subscriptions needs a permission the app does not ask for
            // on every device; an empty list just means "use the default".
            emptyList()
        }
    }
}
