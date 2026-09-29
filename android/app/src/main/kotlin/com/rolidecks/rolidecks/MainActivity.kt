package com.rolidecks.rolidecks

import android.content.BroadcastReceiver
import android.content.Context
import android.content.SharedPreferences
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
import android.provider.Settings
import android.util.DisplayMetrics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URISyntaxException
import java.util.concurrent.Executors

/**
 * The Android half of the launcher: what can be launched, what it looks like,
 * and actually launching it.
 *
 * Everything about *arranging* those apps — grid geometry, ordering, pinning —
 * is plain Dart, so it can be tested without a device.
 */
class MainActivity : FlutterActivity() {
    private val methodChannelName = "rolidecks/launcher"
    private val eventChannelName = "rolidecks/packages"

    /**
     * Renders onto a transparent surface, so the system wallpaper shows through.
     *
     * This is the layer that actually decides it. The theme can ask for the
     * wallpaper and the Scaffold can be transparent, and the deck will still sit
     * on black, because Flutter defaults to an opaque SurfaceView that composites
     * over everything behind it regardless. Transparent mode swaps that for a
     * TextureView with an alpha channel — slightly more expensive to composite,
     * which is the reason it is not the default, and unnoticeable for a launcher
     * that is static between taps.
     */
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    // The package list is one big job; icons are a hundred small ones. On a
    // single thread every icon queues behind every other icon and behind the
    // listing itself, which is what made the all-apps view crawl. Four threads
    // is enough to keep the decode busy without thrashing a phone this small.
    private val worker = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())

    private val requestCreateShortcut = 4011
    private val requestCardImage = 4012
    private val widgetViewType = "rolidecks/widget"
    private val requestBindWidget = 4013
    private val requestConfigureWidget = 4014

    private val appWidgetManager: AppWidgetManager by lazy {
        AppWidgetManager.getInstance(this)
    }

    /**
     * Created once and kept for the life of the activity. The host is what owns
     * every bound widget id, so a second host — or a host rebuilt with a
     * different id — would orphan every widget already on a card.
     */
    private val widgetHost: RolidecksWidgetHost by lazy { RolidecksWidgetHost(this) }

    /** Set while the system's bind or configure screen is up. */
    private var pendingWidgetId: Int? = null
    private var pendingWidgetResult: MethodChannel.Result? = null

    /**
     * Whether the host is currently listening. AppWidgetHost does not report it,
     * and a host that is not listening receives no RemoteViews at all — a widget
     * would stay blank for that reason alone, which is worth being able to rule
     * out.
     */
    private var widgetHostListening = false

    private var pendingImageCard: String? = null
    private var pendingImageResult: MethodChannel.Result? = null

    private fun cardImagesDir(): File =
        File(filesDir, "cardimages").apply { mkdirs() }

    private fun cardImageFile(cardId: String): File =
        File(cardImagesDir(), "${cardId.replace(Regex("[^A-Za-z0-9_-]"), "_")}.jpg")

    /**
     * The image each card is wearing, keyed by card.
     *
     * Read off disk rather than remembered, so a picture that arrived while the
     * launcher was destroyed — which can happen, the picker is another app — is
     * found the next time anyone looks, with nothing to deliver.
     */
    private fun cardImages(): Map<String, String> {
        val files = cardImagesDir().listFiles() ?: return emptyMap()
        return files.filter { it.isFile }.associate {
            it.nameWithoutExtension to it.absolutePath
        }
    }

    private fun pickCardImage(cardId: String, result: MethodChannel.Result) {
        pendingImageCard = cardId
        pendingImageResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("image/*")
        try {
            startActivityForResult(intent, requestCardImage)
        } catch (e: Exception) {
            pendingImageResult = null
            result.success(null)
        }
    }

    /**
     * Copies the chosen image into the app's own storage, scaled down.
     *
     * Copied because the picker grants access to that one URI and the app that
     * owns it may revoke or delete it; scaled because a card is a few hundred
     * pixels wide and decoding a 12-megapixel photo for each of them would cost
     * more memory than the rest of the launcher put together.
     */
    private fun storeCardImage(cardId: String, uri: android.net.Uri): String? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, bounds)
            }
            val target = 1080
            var sample = 1
            while (bounds.outWidth / sample > target * 2) sample *= 2

            val decoded = contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(
                    it,
                    null,
                    BitmapFactory.Options().apply { inSampleSize = sample }
                )
            } ?: return null

            val scale = target.toFloat() / maxOf(decoded.width, decoded.height)
            val bitmap = if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    decoded,
                    (decoded.width * scale).toInt().coerceAtLeast(1),
                    (decoded.height * scale).toInt().coerceAtLeast(1),
                    true
                )
            } else {
                decoded
            }

            val file = cardImageFile(cardId)
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it) }
            file.absolutePath
        } catch (e: Throwable) {
            null
        }
    }

    /**
     * Results are written here before they are announced.
     *
     * This activity is stateNotNeeded and excluded from recents, so Android is
     * free to destroy it while another app's shortcut picker is on screen. The
     * result then lands on a freshly created activity whose Dart side is not
     * listening yet, and a message sent straight down the channel is dropped
     * with nothing to show for it. Writing it down first means the shortcut
     * survives that and is collected when Dart next asks.
     */
    private val shortcutPrefs: SharedPreferences
        get() = getSharedPreferences("rolidecks.shortcuts", Context.MODE_PRIVATE)

    private val pendingKey = "pending"
    private val outcomeKey = "lastOutcome"

    /** Why the last shortcut *launch* ended the way it did. */
    private val launchOutcomeKey = "lastLaunch"
    private var channel: MethodChannel? = null
    private var packageEvents: EventChannel.EventSink? = null
    private var packageReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, methodChannelName
        ).also { it.setMethodCallHandler { call, result -> handle(call, result) } }

        // Registered on the engine rather than created per card: the factory is
        // what hands a card its AppWidgetHostView, and the host it reads from has
        // to be this activity's one.
        flutterEngine.platformViewsController.registry.registerViewFactory(
            widgetViewType,
            WidgetViewFactory({ widgetHost }, appWidgetManager)
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    packageEvents = events
                    registerPackageReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterPackageReceiver()
                    packageEvents = null
                }
            })
    }

    /**
     * Whether this launch is a safe one, decided before anything else runs.
     *
     * Read once and held: the Dart side asks for it while building the deck, and
     * a value that could change underneath that would show widgets on some cards
     * and not others in the same frame.
     */
    private val health: Health by lazy { Health(this) }
    private var startedSafe = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // First, before any of this launch's work: if the previous launch never
        // reached the deck, this one turns widgets off rather than repeating it.
        // A launcher that crashes on startup is relaunched by Android straight
        // away, so nothing outside the process gets a chance to intervene.
        try {
            health.installCrashHandler()
            health.noteLaunchStarted()
            startedSafe = health.safeMode
        } catch (e: Throwable) {
            // Safety plumbing must never be the thing that stops the launcher.
            startedSafe = true
        }
        super.onCreate(savedInstanceState)
        // The pin request can be what started this activity, not only what
        // arrives at a running one.
        handlePinIntent(intent)
    }

    /**
     * Accepts an "add to home screen" request, and keeps what it was given.
     *
     * The ShortcutInfo is captured here rather than looked up afterwards. Every
     * launcher that works does it this way, and it means a shortcut appears
     * because it was accepted rather than because a later query happened to
     * return it — which is one fewer thing that has to be true.
     */
    private fun handlePinIntent(intent: Intent?) {
        if (intent?.action != LauncherApps.ACTION_CONFIRM_PIN_SHORTCUT) return

        val request = try {
            launcherApps.getPinItemRequest(intent)
        } catch (e: Exception) {
            null
        }
        if (request == null ||
            request.requestType != LauncherApps.PinItemRequest.REQUEST_TYPE_SHORTCUT
        ) {
            return
        }

        val shortcut = request.shortcutInfo
        if (shortcut == null || !request.accept()) {
            main.post { channel?.invokeMethod("shortcutFailed", null) }
            return
        }

        val icon = try {
            launcherApps.getShortcutIconDrawable(
                shortcut,
                resources.displayMetrics.densityDpi
            )?.let { rasterise(it, 144) }
        } catch (e: Exception) {
            null
        }

        noteOutcome("pinned ${shortcut.id}")
        recordShortcut(
            label = (shortcut.longLabel ?: shortcut.shortLabel ?: shortcut.id).toString(),
            packageName = shortcut.getPackage(),
            shortcutId = shortcut.id,
            intentUri = null,
            icon = icon
        )
    }

    /**
     * Pressing home while already home should reset to the top level rather
     * than do nothing, the way every stock launcher behaves.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handlePinIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME)) {
            main.post {
                channel?.invokeMethod("homePressed", null)
            }
        }
    }

    /**
     * A host that is not listening receives no RemoteViews updates, so widgets
     * freeze at whatever they last drew — a clock stops, a calendar keeps
     * yesterday. Started and stopped with the activity rather than held open,
     * because listening costs the widgets' own update work while nothing is on
     * screen to show it.
     */
    override fun onStart() {
        super.onStart()
        try {
            widgetHost.startListening()
            widgetHostListening = true
            WidgetNotes.note("host started listening")
        } catch (e: Exception) {
            widgetHostListening = false
            WidgetNotes.note("host could not start listening: ${e.javaClass.simpleName}")
            // Some OEM builds throw here when no widget is bound yet. Not fatal:
            // nothing is listening for, and the next onStart tries again.
        }
    }

    override fun onStop() {
        try {
            widgetHost.stopListening()
            widgetHostListening = false
        } catch (e: Exception) {
            // Symmetric with onStart; a host that never started cannot stop.
        }
        super.onStop()
    }

    override fun onDestroy() {
        unregisterPackageReceiver()
        worker.shutdown()
        super.onDestroy()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listApps" -> onWorker(result) { listApps() }
            "listShortcuts" -> onWorker(result) { listShortcuts() }
            "launchShortcut" -> result.success(
                launchShortcut(
                    call.argument<String>("packageName") ?: "",
                    call.argument<String>("shortcutId") ?: ""
                )
            )
            "shortcutIcon" -> {
                val pkg = call.argument<String>("packageName") ?: ""
                val id = call.argument<String>("shortcutId") ?: ""
                onWorker(result) { shortcutIcon(pkg, id) }
            }
            "appIcon" -> {
                val pkg = call.argument<String>("packageName") ?: ""
                val size = call.argument<Int>("size") ?: 128
                onWorker(result) { appIcon(pkg, size) }
            }
            "launch" -> result.success(launch(call.argument<String>("packageName") ?: ""))
            "openAppInfo" -> {
                openAppInfo(call.argument<String>("packageName") ?: "")
                result.success(null)
            }
            "requestUninstall" -> {
                requestUninstall(call.argument<String>("packageName") ?: "")
                result.success(null)
            }
            "openSettings" -> {
                startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            "openHomeSettings" -> {
                openHomeSettings()
                result.success(null)
            }
            "isDefaultLauncher" -> result.success(isDefaultLauncher())
            "screenMetrics" -> result.success(screenMetrics())
            "shortcutDiagnostics" -> onWorker(result) { shortcutDiagnostics() }
            "takePendingShortcuts" -> result.success(takePendingShortcuts())
            "pickCardImage" -> pickCardImage(call.argument<String>("cardId") ?: "", result)
            "cardImages" -> result.success(cardImages())
            "removeCardImage" -> {
                cardImageFile(call.argument<String>("cardId") ?: "").delete()
                result.success(null)
            }
            "listShortcutMakers" -> onWorker(result) { listShortcutMakers() }
            "createShortcut" -> {
                createShortcut(
                    call.argument<String>("packageName") ?: "",
                    call.argument<String>("activityName") ?: ""
                )
                result.success(null)
            }
            "launchIntentUri" -> result.success(
                launchIntentUri(call.argument<String>("uri") ?: "")
            )
            "listWidgetProviders" -> onWorker(result) { listWidgetProviders() }
            "widgetDiagnostics" -> result.success(widgetDiagnostics())
            "health" -> result.success(
                mapOf(
                    "safeMode" to startedSafe,
                    "lastCrash" to health.lastCrash,
                    "crashCount" to health.crashCount
                )
            )
            "noteDartError" -> {
                health.recordDartError(call.argument<String>("message") ?: "")
                result.success(null)
            }
            "launcherReady" -> {
                health.noteLaunchFinished()
                result.success(null)
            }
            "leaveSafeMode" -> {
                health.leaveSafeMode()
                startedSafe = false
                result.success(null)
            }
            "bindWidget" -> bindWidget(call.argument<String>("provider") ?: "", result)
            "widgetInfo" -> result.success(
                widgetInfo(call.argument<Int>("widgetId") ?: -1)
            )
            "releaseWidget" -> {
                releaseWidget(call.argument<Int>("widgetId") ?: -1)
                result.success(null)
            }
            "reapWidgets" -> {
                reapWidgets(
                    call.argument<List<Int>>("keep") ?: emptyList()
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun onWorker(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    /**
     * Every launchable activity, which is not the same as every installed
     * package: this is the list a launcher is supposed to show, it excludes
     * services and libraries for free, and it correctly surfaces packages that
     * expose more than one launcher entry.
     */
    private fun listApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN, null)
            .addCategory(Intent.CATEGORY_LAUNCHER)

        @Suppress("DEPRECATION")
        val resolved: List<ResolveInfo> = pm.queryIntentActivities(intent, 0)

        return resolved.map { info ->
            val activity = info.activityInfo
            mapOf(
                "packageName" to activity.packageName,
                "activityName" to activity.name,
                "label" to info.loadLabel(pm).toString(),
                "isSystem" to isSystem(activity.packageName)
            )
        }
    }

    private val launcherApps: LauncherApps
        get() = getSystemService(Context.LAUNCHER_APPS_SERVICE) as LauncherApps

    /**
     * The profiles worth asking about, skipping any that cannot answer.
     *
     * A phone can carry a work or clone profile that is locked or stopped, and
     * asking LauncherApps about one throws "User 10 is locked or not running".
     * That is not a SecurityException, so catching only that let it escape and
     * fail the whole call — which took the app list down with it, since
     * shortcuts and apps were fetched together.
     */
    private fun shortcutProfiles(): List<UserHandle> = try {
        launcherApps.profiles
    } catch (e: Throwable) {
        listOf(android.os.Process.myUserHandle())
    }

    /**
     * Runs [work] for one profile, treating any failure as "this profile has
     * nothing to say" rather than as the end of the query. Anything can come
     * back from a profile that is shutting down, so this catches broadly on
     * purpose.
     */
    private fun <T> perProfile(profile: UserHandle, work: (UserHandle) -> T?): T? = try {
        work(profile)
    } catch (e: Throwable) {
        null
    }

    /**
     * Shortcuts other apps have pinned here — a folder from a file manager, a
     * conversation from a chat app.
     *
     * Only the default launcher may read these, which is what
     * hasShortcutHostPermission answers. Before Rolidecks is set as home the
     * list is legitimately empty rather than an error worth reporting.
     */
    private fun listShortcuts(): List<Map<String, Any?>> {
        if (!launcherApps.hasShortcutHostPermission()) return emptyList()

        val query = LauncherApps.ShortcutQuery()
            .setQueryFlags(LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED)

        val out = mutableListOf<Map<String, Any?>>()
        for (profile in shortcutProfiles()) {
            val found: List<ShortcutInfo> =
                perProfile(profile) { launcherApps.getShortcuts(query, it) } ?: emptyList()
            for (shortcut in found) {
                out.add(
                    mapOf(
                        "packageName" to shortcut.getPackage(),
                        "shortcutId" to shortcut.id,
                        "label" to (shortcut.longLabel ?: shortcut.shortLabel ?: shortcut.id)
                            .toString(),
                        "enabled" to shortcut.isEnabled
                    )
                )
            }
        }
        return out
    }

    /// Why the shortcut list is the length it is.
    ///
    /// Pinning happens in another app and lands in a second activity, so when
    /// nothing shows up there is no way to tell from the deck whether the
    /// request never arrived, was refused, or arrived and is simply not being
    /// read. This answers that without a cable.
    private fun shortcutDiagnostics(): Map<String, Any> {
        val host = try {
            launcherApps.hasShortcutHostPermission()
        } catch (e: Throwable) {
            false
        }
        // The exact flag every app checks before offering "add to home
        // screen". Chrome and DuckDuckGo both consult it and quietly do
        // something else when it is false, so if this is false the problem is
        // upstream of anything this launcher does with the request.
        val pinSupported = try {
            (getSystemService(Context.SHORTCUT_SERVICE) as ShortcutManager)
                .isRequestPinShortcutSupported
        } catch (e: Exception) {
            false
        }

        return mapOf(
            "isRequestPinShortcutSupported" to pinSupported,
            "isShortcutHost" to host,
            "pinnedCount" to if (host) {
                try {
                    listShortcuts().size
                } catch (e: Throwable) {
                    -2
                }
            } else {
                -1
            },
            "isDefaultLauncher" to isDefaultLauncher(),
            "profiles" to shortcutProfiles().size,
            // What happened the last time a shortcut was attempted, kept so a
            // failure can be read off the device rather than guessed at.
            "lastOutcome" to (shortcutPrefs.getString(outcomeKey, "none") ?: "none"),
            // And what happened the last time one was *tapped*. Creating a
            // shortcut and launching it fail for unrelated reasons, so one
            // field could not report both.
            "lastLaunch" to (shortcutPrefs.getString(launchOutcomeKey, "none") ?: "none")
        )
    }

    private fun noteOutcome(outcome: String) {
        shortcutPrefs.edit().putString(outcomeKey, outcome).apply()
    }

    private fun noteLaunchOutcome(outcome: String) {
        shortcutPrefs.edit().putString(launchOutcomeKey, outcome).apply()
    }

    /** Hands over everything recorded since the last ask, and forgets it. */
    private fun takePendingShortcuts(): List<Map<String, Any?>> {
        val raw = shortcutPrefs.getString(pendingKey, null) ?: return emptyList()
        shortcutPrefs.edit().remove(pendingKey).apply()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                mapOf(
                    "packageName" to item.optString("packageName"),
                    "shortcutId" to item.optString("shortcutId").ifEmpty { null },
                    "intentUri" to item.optString("intentUri").ifEmpty { null },
                    "label" to item.optString("label"),
                    "icon" to item.optString("icon").ifEmpty { null }
                        ?.let { Base64.decode(it, Base64.NO_WRAP) }
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun recordShortcut(
        label: String,
        packageName: String?,
        shortcutId: String?,
        intentUri: String?,
        icon: ByteArray?,
    ) {
        val existing = shortcutPrefs.getString(pendingKey, null)
        val array = try {
            if (existing == null) JSONArray() else JSONArray(existing)
        } catch (e: Exception) {
            JSONArray()
        }
        array.put(
            JSONObject()
                .put("label", label)
                .put("packageName", packageName ?: "")
                .put("shortcutId", shortcutId ?: "")
                .put("intentUri", intentUri ?: "")
                .put("icon", icon?.let { Base64.encodeToString(it, Base64.NO_WRAP) } ?: "")
        )
        shortcutPrefs.edit().putString(pendingKey, array.toString()).apply()
        // Announce it too, for when the activity did survive — the Dart side
        // ignores a duplicate, since a shortcut is identified by what it opens.
        main.post { channel?.invokeMethod("shortcutsChanged", null) }
    }

    /**
     * Apps that can make a shortcut when asked.
     *
     * The other half of "add to home screen": rather than the app pushing a
     * pin request at whatever launcher will take it, the launcher asks the app
     * to build one. Plenty of apps — file managers especially — only offer
     * this older route, which is why a launcher that handles only pin requests
     * looks like it does not support shortcuts at all.
     */
    @Suppress("DEPRECATION")
    private fun listShortcutMakers(): List<Map<String, Any?>> {
        val intent = Intent(Intent.ACTION_CREATE_SHORTCUT)
        return packageManager.queryIntentActivities(intent, 0).map { info ->
            mapOf(
                "packageName" to info.activityInfo.packageName,
                "activityName" to info.activityInfo.name,
                "label" to info.loadLabel(packageManager).toString()
            )
        }
    }

    private fun createShortcut(packageName: String, activityName: String) {
        val intent = Intent(Intent.ACTION_CREATE_SHORTCUT)
            .setClassName(packageName, activityName)
        try {
            startActivityForResult(intent, requestCreateShortcut)
        } catch (e: Exception) {
            noteOutcome("could not open that app's shortcut screen")
            main.post { channel?.invokeMethod("shortcutFailed", null) }
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == requestBindWidget || requestCode == requestConfigureWidget) {
            val widgetId = pendingWidgetId
            val result = pendingWidgetResult
            pendingWidgetId = null
            pendingWidgetResult = null
            if (widgetId == null) return

            if (resultCode != RESULT_OK) {
                // Declined, or backed out of the widget's own setup. The id is
                // released either way: an allocated id nobody owns is a widget
                // the system keeps updating for a card that never got it.
                releaseWidget(widgetId)
                result?.success(
                    mapOf(
                        "ok" to false,
                        "reason" to if (requestCode == requestBindWidget) {
                            "permission to add widgets was declined"
                        } else {
                            "the widget's setup was cancelled"
                        }
                    )
                )
                return
            }

            // Bound now, so its setup screen can run — configure follows bind
            // rather than replacing it.
            if (requestCode == requestBindWidget) {
                if (result != null) configureOrFinish(widgetId, result)
                return
            }
            result?.success(mapOf("ok" to true, "widgetId" to widgetId))
            return
        }

        if (requestCode == requestCardImage) {
            val cardId = pendingImageCard
            val result = pendingImageResult
            pendingImageCard = null
            pendingImageResult = null

            val uri = if (resultCode == RESULT_OK) data?.data else null
            if (cardId == null || uri == null) {
                result?.success(null)
                return
            }
            worker.execute {
                val path = storeCardImage(cardId, uri)
                // The result may be gone if this activity was rebuilt while the
                // picker was up. The file is on disk either way, and cardImages
                // finds it.
                main.post { result?.success(path) }
            }
            return
        }

        if (requestCode != requestCreateShortcut) return
        if (resultCode != RESULT_OK || data == null) {
            noteOutcome("picker returned resultCode=$resultCode, data=${data != null}")
            return
        }

        // A modern app answers the same request with a pin request rather than
        // the old extras, so try that first: accepting it hands the shortcut to
        // the system, which then lists it like any other pinned one.
        val pinRequest = try {
            launcherApps.getPinItemRequest(data)
        } catch (e: Exception) {
            null
        }
        if (pinRequest != null && pinRequest.isValid) {
            val shortcut = pinRequest.shortcutInfo
            if (shortcut != null && pinRequest.accept()) {
                val icon = try {
                    launcherApps.getShortcutIconDrawable(
                        shortcut,
                        resources.displayMetrics.densityDpi
                    )?.let { rasterise(it, 144) }
                } catch (e: Exception) {
                    null
                }
                noteOutcome("created via pin request")
                recordShortcut(
                    label = (shortcut.longLabel ?: shortcut.shortLabel
                        ?: shortcut.id).toString(),
                    packageName = shortcut.getPackage(),
                    shortcutId = shortcut.id,
                    intentUri = null,
                    icon = icon
                )
                return
            }
        }

        // Otherwise the old shape: an intent, a name and a bitmap. The system
        // does not remember these, so they are handed to Dart to keep.
        val shortcutIntent = data.getParcelableExtra<Intent>(Intent.EXTRA_SHORTCUT_INTENT)
        if (shortcutIntent == null) {
            noteOutcome("result had neither a pin request nor an intent")
            return
        }
        val label = data.getStringExtra(Intent.EXTRA_SHORTCUT_NAME) ?: "Shortcut"
        val icon = data.getParcelableExtra<Bitmap>(Intent.EXTRA_SHORTCUT_ICON)

        noteOutcome("created via intent extras")
        recordShortcut(
            label = label,
            packageName = null,
            shortcutId = null,
            intentUri = shortcutIntent.toUri(Intent.URI_INTENT_SCHEME),
            icon = icon?.let {
                val stream = ByteArrayOutputStream()
                it.compress(Bitmap.CompressFormat.PNG, 100, stream)
                stream.toByteArray()
            }
        )
    }

    /** Launches a shortcut the system does not know about, stored as a URI.
     *
     * Each failure is written down rather than collapsed into a bare `false`.
     * A tile that does nothing when tapped is indistinguishable from a tile
     * that launched something invisible, and the reason — a URI that no longer
     * parses, a target activity that is not exported, an app that has since
     * been uninstalled — is only knowable here, at the throw.
     */
    private fun launchIntentUri(uri: String): Boolean {
        val intent = try {
            Intent.parseUri(uri, Intent.URI_INTENT_SCHEME)
        } catch (e: URISyntaxException) {
            noteLaunchOutcome("legacy: stored URI no longer parses (${e.javaClass.simpleName})")
            return false
        }
        return try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            noteLaunchOutcome("legacy: launched ${intent.component?.flattenToShortString() ?: intent.action ?: "intent"}")
            true
        } catch (e: ActivityNotFoundException) {
            // The usual one: the app that made the shortcut is gone, or the
            // activity it named has been renamed out from under the stored URI.
            noteLaunchOutcome("legacy: nothing resolves ${intent.component?.flattenToShortString() ?: intent.action ?: "intent"}")
            false
        } catch (e: SecurityException) {
            // Android 12+ refuses an outside start of a non-exported activity,
            // which is how a shortcut that used to work stops working after the
            // owning app targets a newer SDK.
            noteLaunchOutcome("legacy: not allowed to start ${intent.component?.flattenToShortString() ?: "it"} (${e.message})")
            false
        } catch (e: Exception) {
            noteLaunchOutcome("legacy: ${e.javaClass.simpleName} ${e.message}")
            false
        }
    }

    private fun launchShortcut(packageName: String, shortcutId: String): Boolean {
        // startShortcut is host-only, and throws SecurityException when this
        // app is not the default launcher. Checked first so that case reports
        // itself as the one thing the user can actually act on, rather than as
        // an anonymous failure alongside genuinely broken shortcuts.
        val host = try {
            launcherApps.hasShortcutHostPermission()
        } catch (e: Throwable) {
            false
        }
        if (!host) {
            noteLaunchOutcome(
                "pinned $packageName/$shortcutId: not the shortcut host — " +
                    "pinned shortcuts only launch while Rolidecks is the default launcher"
            )
            return false
        }
        return try {
            launcherApps.startShortcut(
                packageName,
                shortcutId,
                null,
                null,
                userForShortcut(packageName, shortcutId)
            )
            noteLaunchOutcome("pinned $packageName/$shortcutId: launched")
            true
        } catch (e: Exception) {
            // "Shortcut could not be started" is all startShortcut ever says,
            // for every reason it can refuse — disabled by its app, unpublished
            // since it was pinned, or restored from another phone's backup and
            // never startable here. The reason is knowable, but only by asking
            // separately, so the probe runs on failure and the answer lands in
            // the same field the launcher already reports.
            noteLaunchOutcome(
                "pinned $packageName/$shortcutId: ${e.javaClass.simpleName} ${e.message}" +
                    " — ${probeShortcut(packageName, shortcutId)}"
            )
            false
        }
    }

    /**
     * Why a pinned shortcut would not start, in one line.
     *
     * Every branch is a different fix — reinstall the app, re-add the shortcut
     * from the app that owns it, or accept it can never work on this phone —
     * and they are indistinguishable from the exception alone.
     */
    private fun probeShortcut(packageName: String, shortcutId: String): String {
        val installed = try {
            val info = packageManager.getApplicationInfo(packageName, 0)
            if (info.enabled) "installed" else "installed but disabled"
        } catch (e: PackageManager.NameNotFoundException) {
            return "$packageName is not installed — the shortcut cannot work until it is back"
        }

        // Every flag, not just PINNED: a shortcut its app has stopped
        // publishing stays pinned, and one that is only still visible as
        // "cached" says something different again about why it will not start.
        val query = LauncherApps.ShortcutQuery()
            .setQueryFlags(
                LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED or
                    LauncherApps.ShortcutQuery.FLAG_MATCH_DYNAMIC or
                    LauncherApps.ShortcutQuery.FLAG_MATCH_MANIFEST or
                    LauncherApps.ShortcutQuery.FLAG_GET_KEY_FIELDS_ONLY
            )
            .setPackage(packageName)
            .setShortcutIds(listOf(shortcutId))

        val found = try {
            shortcutProfiles().firstNotNullOfOrNull { profile ->
                perProfile(profile) { launcherApps.getShortcuts(query, it) }
                    ?.firstOrNull()
            }
        } catch (e: Exception) {
            return "$installed; could not be queried (${e.javaClass.simpleName})"
        }

        if (found == null) {
            return "$installed, but it no longer publishes this shortcut — " +
                "re-add it from the app, then remove the old tile"
        }
        if (found.isEnabled) {
            return "$installed and the shortcut is enabled, so the refusal is " +
                "the target activity, not the shortcut " +
                "(activity=${found.activity?.flattenToShortString() ?: "none"})"
        }
        return "$installed, shortcut disabled: ${disabledReasonText(found)}" +
            (found.disabledMessage?.let { " (\"$it\")" } ?: "")
    }

    /** The disabled reason as something readable, not an int. */
    private fun disabledReasonText(shortcut: ShortcutInfo): String =
        when (shortcut.disabledReason) {
            ShortcutInfo.DISABLED_REASON_NOT_DISABLED -> "not disabled"
            ShortcutInfo.DISABLED_REASON_BY_APP ->
                "turned off by the app that made it — re-add it from that app"
            ShortcutInfo.DISABLED_REASON_APP_CHANGED ->
                "the app changed under it (an update moved what it pointed at) — re-add it"
            ShortcutInfo.DISABLED_REASON_VERSION_LOWER ->
                "restored onto an older version of the app than made it — " +
                    "update the app, then re-add it"
            ShortcutInfo.DISABLED_REASON_BACKUP_NOT_SUPPORTED ->
                "came from another phone's backup and cannot be restored — " +
                    "it has to be made again on this phone"
            ShortcutInfo.DISABLED_REASON_SIGNATURE_MISMATCH ->
                "restored from a differently-signed build of the app — re-add it"
            ShortcutInfo.DISABLED_REASON_OTHER_RESTORE_ISSUE ->
                "did not survive a restore — re-add it"
            else -> "reason ${shortcut.disabledReason}"
        }

    private fun userForShortcut(packageName: String, shortcutId: String): UserHandle {
        val query = LauncherApps.ShortcutQuery()
            .setQueryFlags(LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED)
            .setPackage(packageName)
            .setShortcutIds(listOf(shortcutId))
        for (profile in shortcutProfiles()) {
            val found = perProfile(profile) { launcherApps.getShortcuts(query, it) }
            if (!found.isNullOrEmpty()) return profile
        }
        return android.os.Process.myUserHandle()
    }

    private fun shortcutIcon(packageName: String, shortcutId: String): ByteArray? {
        if (!launcherApps.hasShortcutHostPermission()) return null
        val query = LauncherApps.ShortcutQuery()
            .setQueryFlags(LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED)
            .setPackage(packageName)
            .setShortcutIds(listOf(shortcutId))

        for (profile in shortcutProfiles()) {
            val found = perProfile(profile) { launcherApps.getShortcuts(query, it) }
            val shortcut = found?.firstOrNull() ?: continue
            val drawable = launcherApps.getShortcutIconDrawable(
                shortcut,
                resources.displayMetrics.densityDpi
            ) ?: continue
            return rasterise(drawable, 144)
        }
        return null
    }

    private fun isSystem(packageName: String): Boolean = try {
        @Suppress("DEPRECATION")
        val flags = packageManager.getApplicationInfo(packageName, 0).flags
        (flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun launch(packageName: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        // NEW_TASK because the launcher is not the launched app's parent, and
        // RESET_TASK_IF_NEEDED so re-launching returns to the app's root rather
        // than wherever it was left, matching stock launcher behaviour.
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return try {
            startActivity(intent)
            true
        } catch (e: SecurityException) {
            false
        }
    }

    private fun openAppInfo(packageName: String) {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    @Suppress("DEPRECATION")
    private fun requestUninstall(packageName: String) {
        startActivity(
            Intent(Intent.ACTION_DELETE)
                .setData(Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /**
     * Opens the picker that assigns the default home app. There is no API to
     * set it directly — by design — so this is the whole of "make me the
     * launcher".
     */
    private fun openHomeSettings() {
        val intent = Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
        } else {
            // Some skinned builds drop the dedicated home-settings screen.
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    /**
     * Every app widget installed on the phone, for the launcher's own picker.
     *
     * Its own picker rather than ACTION_APPWIDGET_PICK: the system picker returns
     * an already-allocated id owned by *it*, and on several OEM builds returns
     * nothing at all to an app that is not the default launcher. Listing the
     * providers and allocating the id here is the path that behaves the same
     * everywhere.
     */
    private fun listWidgetProviders(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        for (info in appWidgetManager.installedProviders) {
            val component = info.provider ?: continue
            out.add(
                mapOf(
                    "provider" to component.flattenToString(),
                    "packageName" to component.packageName,
                    "label" to info.loadLabel(packageManager).toString(),
                    // In dp: the Dart side compares these against a card's size
                    // to warn when a widget is being put somewhere too small.
                    "minWidth" to pxToDp(info.minWidth),
                    "minHeight" to pxToDp(info.minHeight),
                    "resizable" to (
                        info.resizeMode and AppWidgetProviderInfo.RESIZE_VERTICAL != 0
                        ),
                    "needsConfigure" to (info.configure != null)
                )
            )
        }
        return out
    }

    /**
     * Allocates an id for [provider] and gets it bound, asking the user if it has
     * to.
     *
     * bindAppWidgetIdIfAllowed succeeds only for a caller holding BIND_APPWIDGET,
     * which is a privileged permission a sideloaded launcher cannot hold — so the
     * false it returns is the normal path, not the error path, and the system's
     * own bind dialog is how an ordinary launcher gets permission for one widget
     * at a time.
     */
    private fun bindWidget(provider: String, result: MethodChannel.Result) {
        val component = try {
            android.content.ComponentName.unflattenFromString(provider)
        } catch (e: Exception) {
            null
        }
        if (component == null) {
            result.success(mapOf("ok" to false, "reason" to "unreadable provider"))
            return
        }

        val widgetId = widgetHost.allocateAppWidgetId()
        val bound = try {
            appWidgetManager.bindAppWidgetIdIfAllowed(widgetId, component)
        } catch (e: Exception) {
            false
        }

        if (bound) {
            WidgetNotes.note("bound $provider to id $widgetId without asking")
            configureOrFinish(widgetId, result)
            return
        }
        WidgetNotes.note("id $widgetId allocated; asking to bind $provider")

        // Ask. The id stays allocated while the dialog is up: it is what the
        // system binds on approval, and it is released in onActivityResult if the
        // user declines.
        pendingWidgetId = widgetId
        pendingWidgetResult = result
        val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, component)
        }
        try {
            startActivityForResult(intent, requestBindWidget)
        } catch (e: ActivityNotFoundException) {
            widgetHost.deleteAppWidgetId(widgetId)
            pendingWidgetId = null
            pendingWidgetResult = null
            result.success(
                mapOf("ok" to false, "reason" to "this phone has no widget permission screen")
            )
        }
    }

    /**
     * Runs the widget's own setup screen if it has one, then reports the id.
     *
     * A widget with a configure activity is not usable until it has run — it has
     * no data to draw yet — so a card bound but unconfigured would show a widget
     * that looks broken rather than one waiting to be set up.
     */
    private fun configureOrFinish(widgetId: Int, result: MethodChannel.Result) {
        val info: AppWidgetProviderInfo? = appWidgetManager.getAppWidgetInfo(widgetId)
        if (info == null) {
            // Bound a moment ago and already unreadable. Reported rather than
            // returned as a success: a card given this id would draw nothing.
            WidgetNotes.note("id $widgetId reports no provider straight after binding")
            releaseWidget(widgetId)
            result.success(
                mapOf("ok" to false, "reason" to "the widget did not stay bound")
            )
            return
        }
        if (info.configure == null) {
            WidgetNotes.note("id $widgetId ready, no setup screen")
            result.success(mapOf("ok" to true, "widgetId" to widgetId))
            return
        }
        WidgetNotes.note("id $widgetId needs setup: ${info.configure?.flattenToShortString()}")
        pendingWidgetId = widgetId
        pendingWidgetResult = result
        try {
            widgetHost.startAppWidgetConfigureActivityForResult(
                this, widgetId, 0, requestConfigureWidget, null
            )
        } catch (e: Exception) {
            // Some widgets declare a configure activity that cannot be started by
            // anyone but their own app. Keeping the binding is better than
            // throwing the widget away — most draw a usable default.
            pendingWidgetId = null
            pendingWidgetResult = null
            result.success(mapOf("ok" to true, "widgetId" to widgetId))
        }
    }

    /** What is bound to [widgetId] now, or null if nothing is. */
    private fun widgetInfo(widgetId: Int): Map<String, Any?>? {
        if (widgetId < 0) return null
        val info = appWidgetManager.getAppWidgetInfo(widgetId) ?: return null
        return mapOf(
            "provider" to info.provider?.flattenToString(),
            "packageName" to (info.provider?.packageName ?: ""),
            "label" to info.loadLabel(packageManager).toString(),
            "minHeight" to pxToDp(info.minHeight)
        )
    }

    /** Gives a widget id back to the system. Nothing else frees one. */
    private fun releaseWidget(widgetId: Int) {
        if (widgetId < 0) return
        try {
            widgetHost.deleteAppWidgetId(widgetId)
        } catch (e: Exception) {
            // Already gone is the outcome being asked for.
        }
    }

    /**
     * Releases every id this host holds that no card is using.
     *
     * Ids outlive the cards that referenced them — a card deleted while the
     * launcher was not running, a deck restored from a backup — and an id nobody
     * releases stays bound for the life of the install, keeping the widget's app
     * doing update work for a widget that is on no screen at all.
     */
    private fun reapWidgets(keep: List<Int>) {
        val known = try {
            widgetHost.appWidgetIds
        } catch (e: Exception) {
            return
        }
        for (id in known) {
            if (!keep.contains(id)) releaseWidget(id)
        }
    }

    /**
     * What the launcher can and cannot see about its widgets.
     *
     * The shortcut version of this exists because "nothing appeared" had a
     * handful of possible causes and no way to tell them apart from the deck.
     * A widget that draws nothing is the same problem: the id may not be bound,
     * the host may not be listening, the view may never have been asked for, or
     * it may have been built and given no room. Each leaves a different trace.
     */
    private fun widgetDiagnostics(): Map<String, Any?> {
        val ids = try {
            widgetHost.appWidgetIds.toList()
        } catch (e: Exception) {
            emptyList()
        }

        val bound = ids.map { id ->
            val info = try {
                appWidgetManager.getAppWidgetInfo(id)
            } catch (e: Exception) {
                null
            }
            if (info == null) {
                "$id: nothing bound"
            } else {
                "$id: ${info.provider?.flattenToShortString()}" +
                    " min ${pxToDp(info.minWidth)}x${pxToDp(info.minHeight)}dp" +
                    (if (info.configure != null) " (has setup)" else "")
            }
        }

        val providerCount = try {
            appWidgetManager.installedProviders.size
        } catch (e: Exception) {
            -1
        }

        return mapOf(
            "installedWidgetProviders" to providerCount,
            "hostListening" to widgetHostListening,
            "heldWidgetIds" to ids.size,
            "boundWidgets" to bound,
            // Reported, not assumed. Showing the wallpaper put Flutter on a
            // transparent surface, and a hybrid-composition platform view — which
            // is what an app widget has to be — composites differently against a
            // TextureView than a SurfaceView. That makes the surface in use a
            // prime suspect for a widget that draws nothing, and a suspect is
            // worth confirming rather than reasoning about.
            "flutterSurface" to flutterSurfaceKind(),
            "safeMode" to startedSafe,
            // Newest last, so reading down the list is reading forwards in time.
            "widgetLog" to WidgetNotes.read()
        )
    }

    /** The class Flutter is actually rendering onto, found in the view tree. */
    private fun flutterSurfaceKind(): String {
        val root = window?.decorView as? android.view.ViewGroup ?: return "no window"
        val found = mutableListOf<String>()
        fun walk(view: android.view.View, depth: Int) {
            if (depth > 12) return
            val name = view.javaClass.simpleName
            if (name.startsWith("Flutter")) found.add(name)
            if (view is android.view.ViewGroup) {
                for (i in 0 until view.childCount) walk(view.getChildAt(i), depth + 1)
            }
        }
        walk(root, 0)
        return if (found.isEmpty()) "none found" else found.joinToString(", ")
    }

    private fun isDefaultLauncher(): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        @Suppress("DEPRECATION")
        val resolved: ResolveInfo? =
            packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return resolved?.activityInfo?.packageName == packageName
    }

    /**
     * The real panel geometry, so the Dart side can lay out against measured
     * numbers rather than assumed ones — this screen is an unusual near-square
     * and nothing about it should be guessed.
     */
    private fun screenMetrics(): Map<String, Any> {
        val metrics: DisplayMetrics = resources.displayMetrics
        return mapOf(
            "widthPx" to metrics.widthPixels,
            "heightPx" to metrics.heightPixels,
            "density" to metrics.density,
            "densityDpi" to metrics.densityDpi
        )
    }

    private fun appIcon(packageName: String, size: Int): ByteArray? {
        val drawable: Drawable = try {
            packageManager.getApplicationIcon(packageName)
        } catch (e: PackageManager.NameNotFoundException) {
            return null
        }
        return rasterise(drawable, size)
    }

    private fun rasterise(drawable: Drawable, size: Int): ByteArray {
        val bitmap = when {
            drawable is BitmapDrawable && drawable.bitmap != null ->
                Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)

            // An adaptive icon's two layers are drawn on a 108-unit canvas of
            // which only the middle 72 is meant to be seen; the outer ring is
            // bleed for parallax and for whatever shape a launcher masks to.
            // Rendering the layers at 1.5x and cropping the centre maps that
            // safe zone onto the whole tile, which is what lets the icon fill a
            // rounded square of this launcher's choosing.
            //
            // The layers, not the drawable itself: draw() already applies the
            // system's mask and fits it to the bounds, so cropping its output
            // crops a second time and throws away a third of every icon.
            drawable is AdaptiveIconDrawable &&
                (drawable.background != null || drawable.foreground != null) -> {
                val full = (size * 1.5f).toInt().coerceAtLeast(size)
                val oversized =
                    Bitmap.createBitmap(full, full, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(oversized)
                drawable.background?.apply {
                    setBounds(0, 0, full, full)
                    draw(canvas)
                }
                drawable.foreground?.apply {
                    setBounds(0, 0, full, full)
                    draw(canvas)
                }
                val inset = (full - size) / 2
                Bitmap.createBitmap(oversized, inset, inset, size, size)
            }

            else -> {
                val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                drawable.setBounds(0, 0, size, size)
                drawable.draw(Canvas(bmp))
                bmp
            }
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    /**
     * Installing or removing an app has to redraw the grid immediately — a home
     * screen showing a tile for an app that no longer exists is the most
     * obvious way for a launcher to feel broken.
     */
    private fun registerPackageReceiver() {
        if (packageReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                packageEvents?.success(intent?.data?.encodedSchemeSpecificPart ?: "")
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        packageReceiver = receiver
    }

    private fun unregisterPackageReceiver() {
        packageReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Already gone; nothing to undo.
            }
        }
        packageReceiver = null
    }
}
