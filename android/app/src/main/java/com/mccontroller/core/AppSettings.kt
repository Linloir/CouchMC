package com.mccontroller.core

import android.content.Context
import com.mccontroller.net.Protocol
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject

/**
 * App-wide tunables that aren't part of a specific layout profile.
 *
 * Lives independently from [LayoutProfile] because the user wants these
 * settings (hotbar swipe mode, edge offsets, gesture toggles, volume-key
 * bindings) to be UI-app-wide rather than per-game-profile.
 *
 * Backed by SharedPreferences (`app_settings_v1`), with a [StateFlow]
 * so observing screens (Controller, Settings) live-update on change.
 */
data class AppSettings(
    /** When false, in-game lookpad gestures fire only camera-move deltas — no tap / chain-hold. */
    val inGameQuickClicks: Boolean = true,
    /** When false, UI-mode lookpad gestures drive only the cursor — no tap / double-tap / hold variants. */
    val uiQuickClicks: Boolean = true,

    /** ButtonId the volume-up key sends, or null for "not bound". */
    val volumeUpBinding: Int? = Protocol.ButtonId.MOUSE_LEFT.toInt() and 0xff,
    /** ButtonId the volume-down key sends, or null. */
    val volumeDownBinding: Int? = Protocol.ButtonId.MOUSE_RIGHT.toInt() and 0xff,

    /** Hotbar swipe interpretation — moved out of [LayoutProfile] per user request. */
    val hotbarSwipeMode: HotbarSwipeMode = HotbarSwipeMode.Precise,

    /** Extra horizontal offset applied to widgets anchored to the left edge. */
    val leftMarginOffsetDp: Int = 0,
    /** Extra horizontal offset applied to widgets anchored to the right edge. */
    val rightMarginOffsetDp: Int = 0,
)

/**
 * Singleton-style accessor for [AppSettings]. Mutations are atomic and
 * synchronous (small JSON blob; SharedPreferences `apply()` writes async).
 */
class SettingsStore private constructor(ctx: Context) {

    private val prefs = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val _settings = MutableStateFlow(load())
    val settings: StateFlow<AppSettings> = _settings

    /** Latest snapshot, useful for non-flow consumers (e.g. one-shot reads in onKeyDown). */
    val current: AppSettings get() = _settings.value

    @Synchronized
    fun update(transform: (AppSettings) -> AppSettings) {
        val next = transform(_settings.value)
        if (next == _settings.value) return
        persist(next)
        _settings.value = next
    }

    private fun load(): AppSettings {
        val raw = prefs.getString(KEY_BLOB, null) ?: return AppSettings()
        return try {
            val o = JSONObject(raw)
            AppSettings(
                inGameQuickClicks = o.optBoolean("in_game_quick_clicks", true),
                uiQuickClicks = o.optBoolean("ui_quick_clicks", true),
                volumeUpBinding = if (o.has("vol_up")) o.optInt("vol_up").takeIf { it >= 0 } else
                    Protocol.ButtonId.MOUSE_LEFT.toInt() and 0xff,
                volumeDownBinding = if (o.has("vol_down")) o.optInt("vol_down").takeIf { it >= 0 } else
                    Protocol.ButtonId.MOUSE_RIGHT.toInt() and 0xff,
                hotbarSwipeMode = runCatching {
                    HotbarSwipeMode.valueOf(o.optString("hotbar_swipe", "Precise"))
                }.getOrDefault(HotbarSwipeMode.Precise),
                leftMarginOffsetDp = o.optInt("l_margin", 0),
                rightMarginOffsetDp = o.optInt("r_margin", 0),
            )
        } catch (_: Exception) {
            AppSettings()
        }
    }

    private fun persist(s: AppSettings) {
        val o = JSONObject().apply {
            put("in_game_quick_clicks", s.inGameQuickClicks)
            put("ui_quick_clicks", s.uiQuickClicks)
            put("vol_up", s.volumeUpBinding ?: -1)
            put("vol_down", s.volumeDownBinding ?: -1)
            put("hotbar_swipe", s.hotbarSwipeMode.name)
            put("l_margin", s.leftMarginOffsetDp)
            put("r_margin", s.rightMarginOffsetDp)
        }
        prefs.edit().putString(KEY_BLOB, o.toString()).apply()
    }

    companion object {
        private const val PREFS = "app_settings_v1"
        private const val KEY_BLOB = "blob"

        @Volatile private var instance: SettingsStore? = null

        fun get(ctx: Context): SettingsStore =
            instance ?: synchronized(this) {
                instance ?: SettingsStore(ctx).also { instance = it }
            }
    }
}
