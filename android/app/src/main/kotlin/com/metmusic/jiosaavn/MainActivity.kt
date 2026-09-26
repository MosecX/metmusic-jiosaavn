package com.metmusic.jiosaavn

import android.hardware.display.DisplayManager
import android.os.Build
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity — Flutter default plus a display-mode unlock so devices with
 * 90/120/144 Hz panels actually run at their native refresh rate.
 *
 * Flutter's Android embedding requests the lowest supported display mode by
 * default. Selecting the mode with the widest supported frame interval (i.e.
 * the highest refresh rate) lets the system render at the panel's native
 * rate; Android's own power saving still throttles when idle.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.metmusic.jiosaavn/display"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setHighRefreshRate" -> {
                        val ok = setHighRefreshRate()
                        result.success(ok)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Picks the supported display mode with the highest refresh rate. */
    private fun setHighRefreshRate(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            val display: Display? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                (getSystemService(DISPLAY_SERVICE) as DisplayManager)
                    .getDisplay(Display.DEFAULT_DISPLAY)
            } else {
                window.windowManager.defaultDisplay
            } ?: return false

            val modes = display.supportedModes
            if (modes.isEmpty()) return false

            // Highest refresh rate wins; tie-break on resolution for safety.
            val best = modes.maxWithOrNull(
                compareBy({ it.refreshRate }, { it.physicalWidth })
            ) ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                window.attributes.preferredDisplayModeId = best.modeId
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
