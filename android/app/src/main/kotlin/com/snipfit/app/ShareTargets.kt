package com.snipfit.app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import java.io.File

/**
 * Sends a rendered export straight to one app.
 *
 * Instagram Stories uses Meta's documented ADD_TO_STORY intent (needs the
 * Facebook App ID). TikTok's Share Kit and Snapchat's Creative Kit are SDKs
 * that need their own developer registration; until they're added (see
 * docs/SHARE_KITS.md) those targets use a targeted share intent, and Dart
 * falls back to the system share sheet when this returns false.
 */
class ShareTargets(private val activity: Activity) {
    private val packages = mapOf(
        "instagram" to listOf("com.instagram.android"),
        "tiktok" to listOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill"),
        "snapchat" to listOf("com.snapchat.android"),
        "whatsapp" to listOf("com.whatsapp"),
    )

    private fun installed(pkg: String): Boolean = try {
        activity.packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun installedPackage(target: String): String? = packages[target]?.firstOrNull { installed(it) }

    fun isInstalled(target: String): Boolean = installedPackage(target) != null

    fun shareTo(target: String, path: String, mimeType: String, appIds: Map<String, String>, caption: String?): Boolean {
        val pkg = installedPackage(target) ?: return false
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.snipfit.fileprovider", File(path))
        activity.grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val intent = when (target) {
            "instagram" -> {
                val appId = appIds["facebook"].orEmpty()
                if (appId.isEmpty()) return false
                Intent("com.instagram.share.ADD_TO_STORY").apply {
                    putExtra("source_application", appId)
                    setDataAndType(uri, mimeType)
                }
            }
            else -> Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                if (caption != null) putExtra(Intent.EXTRA_TEXT, caption)
            }
        }.apply {
            setPackage(pkg)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (intent.resolveActivity(activity.packageManager) == null) return false
        activity.startActivity(intent)
        return true
    }
}
