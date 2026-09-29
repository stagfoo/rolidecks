package com.rolidecks.rolidecks

import android.content.Context
import android.content.SharedPreferences
import java.io.PrintWriter
import java.io.StringWriter

/**
 * Keeps the launcher startable.
 *
 * A launcher is the home app, so a crash on startup is not one crash: Android
 * relaunches it immediately and it crashes again, and the phone has no home
 * screen until something breaks the cycle from inside. Nothing else can — there
 * is no window in which to change a setting.
 *
 * So each launch writes down that it has started and, separately, that it got as
 * far as drawing. A launch that begins while the previous one never reached the
 * second mark did not survive, and this one turns off the part most likely to
 * have killed it rather than repeating it.
 */
class Health(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("rolidecks.health", Context.MODE_PRIVATE)

    /**
     * True when the previous launch died before the deck was on screen.
     *
     * Sticky once set. A flag recomputed each launch would give a working
     * launcher every other time — crash, safe, crash, safe — which is worse than
     * either state, because nothing about it looks like a fault to be fixed.
     */
    val safeMode: Boolean get() = prefs.getBoolean(keySafeMode, false)

    val lastCrash: String get() = prefs.getString(keyLastCrash, "") ?: ""

    val crashCount: Int get() = prefs.getInt(keyCrashCount, 0)

    /**
     * Called as the activity starts. Decides whether this launch is a safe one.
     */
    fun noteLaunchStarted() {
        val previousNeverFinished = prefs.getBoolean(keyLaunchPending, false)
        prefs.edit()
            .putBoolean(keyLaunchPending, true)
            .apply()
        if (previousNeverFinished) {
            prefs.edit()
                .putBoolean(keySafeMode, true)
                .putInt(keyCrashCount, crashCount + 1)
                .apply()
        }
    }

    /** Called once the deck is actually on screen. */
    fun noteLaunchFinished() {
        prefs.edit().putBoolean(keyLaunchPending, false).apply()
    }

    /**
     * Turns widgets back on, for when the cause has been dealt with.
     *
     * Deliberately explicit. Clearing it automatically on a good launch would put
     * the launcher straight back into the crash it just escaped.
     */
    fun leaveSafeMode() {
        prefs.edit()
            .putBoolean(keySafeMode, false)
            .putBoolean(keyLaunchPending, false)
            .apply()
    }

    /** A Dart exception, which never reaches the Java crash handler. */
    fun recordDartError(message: String) {
        if (message.isEmpty()) return
        prefs.edit().putString(keyLastCrash, "dart: ${message.take(600)}").apply()
    }

    fun recordCrash(thread: String, error: Throwable) {
        val trace = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
        // Trimmed: this is read on a phone screen and pasted into a message, and
        // the first frames are the ones that say what happened.
        val short = trace.lineSequence().take(24).joinToString("\n")
        prefs.edit()
            .putString(keyLastCrash, "on $thread: $short")
            .apply()
    }

    /**
     * Records anything that kills a thread, then lets the default handler do what
     * it was going to do.
     *
     * Chained rather than replaced: swallowing the crash would leave the process
     * in whatever state caused it, which is a worse failure than stopping.
     */
    fun installCrashHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                recordCrash(thread.name, error)
            } catch (e: Throwable) {
                // A crash handler that crashes hides the crash it was handling.
            }
            previous?.uncaughtException(thread, error)
        }
    }

    private companion object {
        const val keyLaunchPending = "launchPending"
        const val keySafeMode = "safeMode"
        const val keyLastCrash = "lastCrash"
        const val keyCrashCount = "crashCount"
    }
}
