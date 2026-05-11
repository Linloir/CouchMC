package com.mccontroller.ui

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.fragment.app.Fragment
import androidx.fragment.app.commit
import com.mccontroller.R
import com.mccontroller.databinding.ActivityMainBinding

/**
 * Top-level container. Holds the bottom navigation bar and a single
 * [androidx.fragment.app.FragmentContainerView] that swaps between
 * [HomeFragment] and [SettingsFragment] when the user taps the bottom
 * tabs. Tabs are stateless — re-tapping the active tab is a no-op.
 *
 * No back-stack: pressing Back from either tab exits the app. (Standard
 * pattern for two-tab phone apps.)
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        applyEdgeToEdgeInsets()

        binding.bottomNav.setOnItemSelectedListener { item ->
            val tag = when (item.itemId) {
                R.id.nav_home -> TAG_HOME
                R.id.nav_settings -> TAG_SETTINGS
                else -> return@setOnItemSelectedListener false
            }
            switchTo(tag)
            true
        }
        binding.bottomNav.setOnItemReselectedListener { /* no-op */ }

        if (savedInstanceState == null) {
            // Don't rely on setSelectedItemId(R.id.nav_home) to bootstrap
            // the home fragment: BottomNavigationView's default selection
            // is already the first menu item (nav_home), so setting it
            // again doesn't fire the OnItemSelectedListener and switchTo
            // never runs — the home fragment was never added until the
            // user manually tab-swapped. Explicitly invoke switchTo here.
            switchTo(TAG_HOME)
        }
    }

    private fun switchTo(tag: String) {
        val existing = supportFragmentManager.findFragmentByTag(tag)
        supportFragmentManager.commit {
            // Hide every other fragment, then show or add the target one.
            // Hiding (vs replace+detach) keeps each fragment's view state —
            // scroll position, expanded toggles, etc. — across tab swaps.
            for (frag in supportFragmentManager.fragments) {
                if (frag != existing) hide(frag)
            }
            if (existing != null) {
                show(existing)
            } else {
                add(R.id.fragment_container, newFragmentFor(tag), tag)
            }
        }
    }

    private fun newFragmentFor(tag: String): Fragment = when (tag) {
        TAG_HOME -> HomeFragment()
        TAG_SETTINGS -> SettingsFragment()
        else -> error("Unknown fragment tag: $tag")
    }

    private fun applyEdgeToEdgeInsets() {
        // Status bar inset is consumed inside each fragment's app bar.
        // Bottom inset is applied to the BottomNavigationView so it
        // breathes above the gesture pill / nav bar.
        ViewCompat.setOnApplyWindowInsetsListener(binding.bottomNav) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.updatePadding(bottom = bars.bottom)
            insets
        }
        // BottomNavigationView auto-installs a long-press tooltip on each
        // item containing the item's title. Since `labelVisibilityMode`
        // is `labeled`, the title is *already* visible directly under the
        // icon — the tooltip is redundant. And the system positions it
        // near the touch point rather than above the icon, which led to
        // the tooltip floating up and to the side of where the user
        // pressed. Walk the view tree once after layout and clear
        // tooltipText so the long-press becomes a silent no-op.
        binding.bottomNav.post { clearTooltipsRecursive(binding.bottomNav) }
    }

    private fun clearTooltipsRecursive(v: View) {
        v.tooltipText = null
        if (v is ViewGroup) {
            for (i in 0 until v.childCount) clearTooltipsRecursive(v.getChildAt(i))
        }
    }

    companion object {
        private const val TAG_HOME = "home"
        private const val TAG_SETTINGS = "settings"
    }
}
