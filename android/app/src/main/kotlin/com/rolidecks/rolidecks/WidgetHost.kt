package com.rolidecks.rolidecks

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.Context
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * The launcher's app widget host.
 *
 * A host id identifies this launcher to the widget system and has to stay the
 * same across launches, or every widget bound under a previous id is orphaned:
 * the ids stored on the cards would still exist but belong to a host that no
 * longer asks for them, and every widget card would come back blank.
 */
const val WIDGET_HOST_ID = 0x52444B // "RDK"

/**
 * Widget views are created by the host and then handed to Flutter, so both sides
 * need the same one. Keyed by widget id rather than by platform-view id: the deck
 * rebuilds constantly and a card scrolling out and back should re-show the widget
 * it already had rather than ask the host for a second view onto it.
 */
class RolidecksWidgetHost(context: Context) : AppWidgetHost(context, WIDGET_HOST_ID) {
    /**
     * Uses the default AppWidgetHostView. Subclassing it to intercept errors is
     * the usual reason to override this, and doing nothing is the reason not to:
     * the default already draws the provider's error layout when RemoteViews
     * fail to inflate, which is more use than a blank we substituted ourselves.
     */
    override fun onCreateView(
        context: Context,
        appWidgetId: Int,
        appWidget: AppWidgetProviderInfo?
    ): AppWidgetHostView = super.onCreateView(context, appWidgetId, appWidget)
}

/**
 * Hands Flutter an [AppWidgetHostView] for the widget id it asks for.
 *
 * Hybrid composition, not a virtual display: a widget's content is RemoteViews
 * owned by another process, and in a virtual display its taps land in the wrong
 * place and its list widgets do not scroll at all. That is also why the Dart side
 * uses PlatformViewLink with an expensive controller rather than a plain
 * AndroidView.
 */
class WidgetViewFactory(
    private val hostProvider: () -> RolidecksWidgetHost?,
    private val appWidgetManager: AppWidgetManager
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val widgetId = (params?.get("widgetId") as? Number)?.toInt() ?: -1
        return WidgetPlatformView(context, widgetId, hostProvider(), appWidgetManager)
    }
}

private class WidgetPlatformView(
    context: Context,
    widgetId: Int,
    host: RolidecksWidgetHost?,
    appWidgetManager: AppWidgetManager
) : PlatformView {

    private val view: View = build(context, widgetId, host, appWidgetManager)

    private fun build(
        context: Context,
        widgetId: Int,
        host: RolidecksWidgetHost?,
        appWidgetManager: AppWidgetManager
    ): View {
        val info = if (widgetId >= 0) appWidgetManager.getAppWidgetInfo(widgetId) else null
        // A null info means the id is not bound any more — the widget's app was
        // uninstalled, or its data was cleared. An empty view rather than a
        // crash: the card is still there to be given another widget, and the Dart
        // side is told separately so it can say so.
        if (host == null || info == null) return View(context)
        return host.createView(context.applicationContext, widgetId, info).apply {
            setAppWidget(widgetId, info)
            // The card decides how big the widget is, so the host view is told
            // its size rather than measuring itself from the provider's minimum.
            // Without this a widget whose declared minimum is taller than the
            // card overflows it instead of resizing into it.
            updateAppWidgetSize(Bundle.EMPTY, 0, 0, 0, 0)
        }
    }

    override fun getView(): View = view

    /**
     * The host owns the view, not this wrapper, so nothing is torn down here.
     * Deleting the widget id is what actually releases a widget, and that happens
     * when the card is deleted or rebound — a card scrolling off screen must not
     * take its widget with it.
     */
    override fun dispose() {}
}

/** dp for a widget's reported size; RemoteViews sizing is in dp, not pixels. */
fun Context.pxToDp(px: Int): Int = (px / resources.displayMetrics.density).toInt()

fun Context.dpToPx(dp: Int): Int = TypedValue.applyDimension(
    TypedValue.COMPLEX_UNIT_DIP,
    dp.toFloat(),
    resources.displayMetrics
).toInt()
