package com.erebrus.vpn

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * Switches which launcher `<activity-alias>` is enabled, so the app's name and
 * icon in the launcher can change without a reinstall.
 *
 * The alias names are owned by `AndroidManifest.xml` and passed in from Dart
 * ([lib/settings/disguise_profile.dart]) rather than duplicated here: one list
 * in the manifest, one list in Dart, and a test that holds them together.
 *
 * Nothing here hides data. A disguise hides that Erebrus is *installed*; an
 * unlocked device still hands over everything the app stores.
 */
object AppDisguise {

    /** The alias that ships enabled: the app under its own name and icon. */
    const val DEFAULT_ALIAS = ".LauncherDefault"

    /**
     * Whether the launcher is showing something other than Erebrus.
     *
     * Used to decide whether this window hides itself from screenshots and the
     * recents thumbnail. Asking the package manager rather than caching it
     * means the answer is right even on the first frame after a cold start,
     * before any Dart code has run.
     */
    fun isDisguised(context: Context): Boolean {
        val pm = context.packageManager
        val component = component(context, DEFAULT_ALIAS)
        val state = try {
            pm.getComponentEnabledSetting(component)
        } catch (_: IllegalArgumentException) {
            return false
        }
        return when (state) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> false
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT ->
                !manifestEnabled(pm, context, DEFAULT_ALIAS)
            else -> true
        }
    }

    /**
     * Enables [alias] and disables every other alias in [all].
     *
     * Order matters: the incoming alias is enabled **before** the outgoing one
     * is disabled. Several OEM launchers drop the app from the launcher
     * entirely if it passes through a moment with no enabled MAIN/LAUNCHER
     * component, and the user's only way back is to reinstall.
     *
     * Returns false when [alias] is not one of [all] or the component does not
     * exist, which means the manifest and the Dart list have drifted apart.
     */
    fun set(context: Context, alias: String, all: List<String>): Boolean {
        if (alias.isBlank() || !all.contains(alias)) return false
        val pm = context.packageManager
        if (!enable(pm, component(context, alias), PackageManager.COMPONENT_ENABLED_STATE_ENABLED)) {
            return false
        }
        for (other in all) {
            if (other == alias) continue
            enable(pm, component(context, other), PackageManager.COMPONENT_ENABLED_STATE_DISABLED)
        }
        return true
    }

    /**
     * The alias the launcher is currently showing, or null when none of [all]
     * is enabled — which is only reachable if a `set` was interrupted.
     *
     * A component left at COMPONENT_ENABLED_STATE_DEFAULT still follows the
     * manifest, so the default alias reads as enabled before the first switch.
     */
    fun current(context: Context, all: List<String>): String? {
        val pm = context.packageManager
        for (alias in all) {
            val state = try {
                pm.getComponentEnabledSetting(component(context, alias))
            } catch (_: IllegalArgumentException) {
                continue
            }
            val on = when (state) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> manifestEnabled(pm, context, alias)
                else -> false
            }
            if (on) return alias
        }
        return null
    }

    private fun component(context: Context, alias: String) =
        ComponentName(context.packageName, context.packageName + alias)

    private fun enable(pm: PackageManager, component: ComponentName, state: Int): Boolean {
        return try {
            pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
            true
        } catch (_: IllegalArgumentException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    /** Whether the manifest ships this alias enabled. */
    private fun manifestEnabled(pm: PackageManager, context: Context, alias: String): Boolean {
        return try {
            @Suppress("DEPRECATION")
            val info = pm.getActivityInfo(
                component(context, alias),
                PackageManager.MATCH_DISABLED_COMPONENTS,
            )
            info.enabled
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }
}
