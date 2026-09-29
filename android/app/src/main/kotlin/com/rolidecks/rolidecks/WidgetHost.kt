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
 * What happened the last few times a widget view was built.
 *
 * A widget that draws nothing is the hardest state to explain from the outside:
 * the card is the right height, the deck is fine, and the space where the widget
 * should be is simply empty. Every branch that can end in that blank writes down
 * which one it was, so the answer is readable off the phone rather than inferred.
 */
object WidgetNotes {
    private const val keep = 8
    private val lines = ArrayDeque<String>()

    @Synchronized
    fun note(line: String) {
        lines.addLast(line)
        while (lines.size > keep) lines.removeFirst()
    }

    @Synchronized
    fun read(): List<String> = lines.toList()

    @Synchronized
    fun clear() = lines.clear()
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
        WidgetNotes.note("factory asked for widget $widgetId (view $viewId)")
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
        if (widgetId < 0) {
            WidgetNotes.note("no widget id reached the factory")
            return View(context)
        }
        if (host == null) {
            WidgetNotes.note("widget $widgetId: no host — the activity is gone")
            return View(context)
        }
        val info = try {
            appWidgetManager.getAppWidgetInfo(widgetId)
        } catch (e: Exception) {
            WidgetNotes.note("widget $widgetId: info threw ${e.javaClass.simpleName}")
            null
        }
        // A null info means the id is not bound any more — the widget's app was
        // uninstalled, or its data was cleared. An empty view rather than a
        // crash: the card is still there to be given another widget.
        if (info == null) {
            WidgetNotes.note(
                "widget $widgetId: nothing bound to this id — it was never bound, " +
                    "or its app is gone"
            )
            return View(context)
        }

        return try {
            val view = host.createView(context.applicationContext, widgetId, info)
            view.setAppWidget(widgetId, info)
            WidgetNotes.note(
                "widget $widgetId: view built for ${info.provider?.flattenToShortString()}" +
                    " (min ${context.pxToDp(info.minWidth)}x${context.pxToDp(info.minHeight)}dp)"
            )
            // The size is sent once the view has been laid out, because only then
            // is there a size to send.
            //
            // It used to be sent immediately as (0, 0, 0, 0), meaning "fit
            // whatever you are given" — which is not what a widget reads it as.
            // Those numbers become OPTION_APPWIDGET_MIN_WIDTH and friends, and a
            // widget told it has zero by zero dp to work with is entitled to draw
            // nothing at all, which is exactly what several of them do.
            view.post {
                val widthDp = context.pxToDp(view.width)
                val heightDp = context.pxToDp(view.height)
                if (widthDp > 0 && heightDp > 0) {
                    // Min and max both the real size: the card is a fixed box, so
                    // there is no range for the widget to choose within.
                    view.updateAppWidgetSize(Bundle.EMPTY, widthDp, heightDp, widthDp, heightDp)
                    WidgetNotes.note(
                        "widget $widgetId: laid out ${view.width}x${view.height}px" +
                            " (${widthDp}x${heightDp}dp), children=${view.childCount}"
                    )
                } else {
                    // A zero-sized host view is the other way a widget ends up
                    // blank, and it is not the widget's doing — nothing was given
                    // any room to draw in.
                    WidgetNotes.note(
                        "widget $widgetId: host view laid out at ${view.width}x${view.height}px" +
                            " — no room to draw, so nothing was asked of the widget"
                    )
                }
            }
            view
        } catch (e: Exception) {
            WidgetNotes.note(
                "widget $widgetId: createView threw ${e.javaClass.simpleName} ${e.message}"
            )
            View(context)
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
