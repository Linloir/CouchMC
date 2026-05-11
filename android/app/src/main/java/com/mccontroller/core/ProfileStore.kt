package com.mccontroller.core

import android.content.Context
import org.json.JSONObject

/**
 * Persists named [LayoutProfile]s to SharedPreferences as a single JSON blob.
 *
 * Schema (v1):
 * ```
 * {
 *   "active": "Default",
 *   "profiles": {
 *     "Default": { "name": "...", "in_game": { ... }, "ui_mode": { ... } },
 *     ...
 *   }
 * }
 * ```
 *
 * On first read with no stored data, the Default profile is auto-seeded.
 */
class ProfileStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun loadAll(): Pair<List<LayoutProfile>, String> {
        val raw = prefs.getString(KEY_BLOB, null)
        if (raw.isNullOrEmpty()) {
            // First run: seed with Default and persist immediately.
            saveAll(listOf(DefaultLayouts.DEFAULT_PROFILE), DefaultLayouts.DEFAULT_PROFILE.name)
            return listOf(DefaultLayouts.DEFAULT_PROFILE) to DefaultLayouts.DEFAULT_PROFILE.name
        }

        return try {
            val obj = JSONObject(raw)
            val active = obj.optString("active", DefaultLayouts.DEFAULT_PROFILE.name)
            val profilesObj = obj.optJSONObject("profiles")
            val profiles = mutableListOf<LayoutProfile>()
            if (profilesObj != null) {
                val names = profilesObj.keys()
                while (names.hasNext()) {
                    val name = names.next()
                    val pObj = profilesObj.getJSONObject(name)
                    profiles.add(parseProfile(pObj))
                }
            }
            if (profiles.isEmpty()) profiles.add(DefaultLayouts.DEFAULT_PROFILE)
            profiles.toList() to active
        } catch (e: Exception) {
            // Corrupt JSON — fall back to defaults.
            listOf(DefaultLayouts.DEFAULT_PROFILE) to DefaultLayouts.DEFAULT_PROFILE.name
        }
    }

    fun saveAll(profiles: List<LayoutProfile>, activeName: String) {
        val profilesObj = JSONObject()
        for (p in profiles) {
            profilesObj.put(p.name, profileToJson(p))
        }
        val root = JSONObject().apply {
            put("active", activeName)
            put("profiles", profilesObj)
        }
        prefs.edit().putString(KEY_BLOB, root.toString()).apply()
    }

    fun setActive(name: String) {
        val (profiles, _) = loadAll()
        if (profiles.any { it.name == name }) {
            saveAll(profiles, name)
        }
    }

    // ===== JSON helpers =====

    private fun profileToJson(p: LayoutProfile): JSONObject = JSONObject().apply {
        put("name", p.name)
        put("in_game", modeLayoutToJson(p.inGame))
        put("ui_mode", modeLayoutToJson(p.uiMode))
        put("hotbar_swipe_mode", p.hotbarSwipeMode.name)
    }

    private fun modeLayoutToJson(m: ModeLayout): JSONObject = JSONObject().apply {
        val widgetsObj = JSONObject()
        for ((id, spec) in m.widgets) {
            widgetsObj.put(id, widgetSpecToJson(spec))
        }
        put("widgets", widgetsObj)
        put("left_offset_dp", m.leftOffsetDp.toDouble())
        put("right_offset_dp", m.rightOffsetDp.toDouble())
    }

    private fun widgetSpecToJson(w: WidgetSpec): JSONObject = JSONObject().apply {
        put("id", w.id)
        put("anchor", w.anchor.name)
        put("edge_dp", w.edgeMarginDp.toDouble())
        put("vert_dp", w.verticalMarginDp.toDouble())
        put("width_dp", w.widthDp.toDouble())
        put("height_dp", w.heightDp.toDouble())
    }

    private fun parseProfile(obj: JSONObject): LayoutProfile = LayoutProfile(
        name = obj.optString("name", "Unnamed"),
        inGame = parseModeLayout(obj.optJSONObject("in_game") ?: JSONObject(), DefaultLayouts.IN_GAME),
        uiMode = parseModeLayout(obj.optJSONObject("ui_mode") ?: JSONObject(), DefaultLayouts.UI_MODE),
        hotbarSwipeMode = runCatching {
            HotbarSwipeMode.valueOf(obj.optString("hotbar_swipe_mode", "Precise"))
        }.getOrDefault(HotbarSwipeMode.Precise),
    )

    private fun parseModeLayout(obj: JSONObject, fallback: ModeLayout): ModeLayout {
        val widgetsObj = obj.optJSONObject("widgets")
        val widgets = mutableMapOf<String, WidgetSpec>()
        // Start with fallback so any new widget IDs from defaults get filled in.
        widgets.putAll(fallback.widgets)
        if (widgetsObj != null) {
            val keys = widgetsObj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                val w = parseWidgetSpec(widgetsObj.getJSONObject(k))
                widgets[w.id] = w
            }
        }
        return ModeLayout(
            widgets = widgets.toMap(),
            leftOffsetDp = obj.optDouble("left_offset_dp", 0.0).toFloat(),
            rightOffsetDp = obj.optDouble("right_offset_dp", 0.0).toFloat(),
        )
    }

    private fun parseWidgetSpec(obj: JSONObject): WidgetSpec = WidgetSpec(
        id = obj.optString("id"),
        anchor = runCatching { Anchor.valueOf(obj.optString("anchor")) }
            .getOrDefault(Anchor.BottomStart),
        edgeMarginDp = obj.optDouble("edge_dp", 0.0).toFloat(),
        verticalMarginDp = obj.optDouble("vert_dp", 0.0).toFloat(),
        widthDp = obj.optDouble("width_dp", 0.0).toFloat(),
        heightDp = obj.optDouble("height_dp", 0.0).toFloat(),
    )

    companion object {
        private const val PREFS_NAME = "layout_profiles_v1"
        private const val KEY_BLOB = "blob"
    }
}
