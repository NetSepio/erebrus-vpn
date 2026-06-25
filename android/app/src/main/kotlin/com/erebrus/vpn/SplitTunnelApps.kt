package com.erebrus.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/** Lists user-launchable apps for per-app split tunnel selection. */
object SplitTunnelApps {
    fun listUserApps(ctx: Context): List<Map<String, String>> {
        val pm = ctx.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val flags = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            PackageManager.MATCH_ALL
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_META_DATA
        }
        val resolved = pm.queryIntentActivities(launcher, flags)
        val self = ctx.packageName
        return resolved
            .asSequence()
            .map { it.activityInfo.packageName }
            .filter { it != self }
            .distinct()
            .sorted()
            .map { pkg ->
                val label = runCatching {
                    pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
                }.getOrDefault(pkg)
                mapOf("package" to pkg, "label" to label)
            }
            .toList()
    }
}