// main activity
// @params none
// enables android edge-to-edge and display cutout handling

package com.echoproof.app

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Debug
import android.view.WindowManager
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.Locale
import kotlin.math.max

class MainActivity : FlutterFragmentActivity() {
    private var shortcutChannel: MethodChannel? = null
    private var securityChannel: MethodChannel? = null
    private val createShortcutId = "create_echo"
    private val profileShortcutId = "profile"
    private val launcherShortcutIds = listOf(createShortcutId, profileShortcutId)

    override fun onCreate(savedInstanceState: Bundle?) {
        // keep screenshots and non-secure display capture blocked before flutter draws
        // dart keeps the same flag alive so modal routes cannot accidentally clear it
        enforceSecureWindow()
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(
                Color.TRANSPARENT,
                Color.TRANSPARENT
            ),
            navigationBarStyle = SystemBarStyle.light(
                Color.WHITE,
                Color.WHITE
            )
        )
        super.onCreate(savedInstanceState)
        window.navigationBarColor = Color.WHITE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.navigationBarDividerColor = Color.WHITE
        }
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightNavigationBars = true
            isAppearanceLightStatusBars = true
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shortcutChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "echoproof/quick_actions"
        )
        shortcutChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "installShortcuts" -> {
                    installLauncherShortcuts(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "clearShortcuts" -> {
                    clearLauncherShortcuts()
                    result.success(null)
                }
                "getInitialShortcut" -> result.success(shortcutFrom(intent))
                else -> result.notImplemented()
            }
        }
        securityChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "echoproof/security_signals"
        )
        securityChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "securitySignals" -> result.success(securitySignals())
                "enforceSecureWindow" -> {
                    enforceSecureWindow()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shortcutFrom(intent)?.let { shortcut ->
            shortcutChannel?.invokeMethod("shortcut", shortcut)
        }
    }

    private fun shortcutFrom(intent: Intent?): String? {
        return intent?.getStringExtra("echoproof_shortcut")
    }

    private fun installLauncherShortcuts(args: Map<*, *>?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        val manager = getSystemService(ShortcutManager::class.java) ?: return
        val includeProfile = args?.get("includeProfile") as? Boolean ?: false

        // pinned shortcuts can be disabled on logout, so restore valid ones on login
        try {
            val idsToEnable = if (includeProfile) {
                launcherShortcutIds
            } else {
                listOf(createShortcutId)
            }
            manager.enableShortcuts(idsToEnable)
        } catch (_: IllegalArgumentException) {
            // some launchers reject unknown pinned ids before the first install
        }

        val shortcuts = mutableListOf(buildCreateShortcut())
        if (includeProfile) {
            shortcuts += buildProfileShortcut(args)
        } else {
            disableProfileShortcut(manager)
        }
        manager.dynamicShortcuts = shortcuts
        try {
            manager.updateShortcuts(shortcuts)
        } catch (_: IllegalArgumentException) {
            // launchers can reject updates for shortcuts they do not know yet
        }
    }

    private fun buildCreateShortcut(): ShortcutInfo {
        val createIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra("echoproof_shortcut", createShortcutId)
        }
        return ShortcutInfo.Builder(this, createShortcutId)
            .setShortLabel("Create")
            .setLongLabel("Create echo")
            .setIcon(Icon.createWithResource(this, R.drawable.ic_shortcut_create))
            .setIntent(createIntent)
            .build()
    }

    private fun buildProfileShortcut(args: Map<*, *>?): ShortcutInfo {
        val shortLabel = (args?.get("profileShortLabel") as? String)
            ?.takeIf { it.isNotBlank() }
            ?: "Profile"
        val longLabel = (args?.get("profileLongLabel") as? String)
            ?.takeIf { it.isNotBlank() }
            ?: "Your profile"
        val profileIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra("echoproof_shortcut", profileShortcutId)
        }
        return ShortcutInfo.Builder(this, profileShortcutId)
            .setShortLabel(shortLabel)
            .setLongLabel(longLabel)
            .setIcon(profileShortcutIcon(args))
            .setIntent(profileIntent)
            .build()
    }

    private fun profileShortcutIcon(args: Map<*, *>?): Icon {
        val bytes = args?.get("profileIconBytes") as? ByteArray
        return iconFromProfileBytes(bytes)
            ?: Icon.createWithResource(this, R.drawable.ic_shortcut_profile)
    }

    private fun iconFromProfileBytes(bytes: ByteArray?): Icon? {
        if (bytes == null || bytes.isEmpty()) return null
        return try {
            val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
            val density = resources.displayMetrics.density
            val size = (72 * density).toInt().coerceAtLeast(96)
            val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val center = size / 2f
            val radius = center

            val background = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(222, 241, 232)
            }
            canvas.drawCircle(center, center, radius, background)

            val shader = BitmapShader(
                source,
                Shader.TileMode.CLAMP,
                Shader.TileMode.CLAMP
            )
            val matrix = Matrix()
            val scale = max(
                size / source.width.toFloat(),
                size / source.height.toFloat()
            )
            val dx = (size - source.width * scale) / 2f
            val dy = (size - source.height * scale) / 2f
            matrix.setScale(scale, scale)
            matrix.postTranslate(dx, dy)
            shader.setLocalMatrix(matrix)

            val avatarPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.shader = shader
            }
            val inset = size * 0.08f
            canvas.drawCircle(center, center, radius - inset, avatarPaint)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Icon.createWithAdaptiveBitmap(output)
            } else {
                Icon.createWithBitmap(output)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun clearLauncherShortcuts() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        val manager = getSystemService(ShortcutManager::class.java) ?: return

        // keep create available because the router protects posting behind login
        manager.dynamicShortcuts = listOf(buildCreateShortcut())
        disableProfileShortcut(manager)
    }

    private fun disableProfileShortcut(manager: ShortcutManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        manager.removeDynamicShortcuts(listOf(profileShortcutId))

        // pinned profile shortcuts can outlive a logout on some launchers
        manager.disableShortcuts(
            listOf(profileShortcutId),
            "Sign in to EchoProof to use this shortcut"
        )
    }

    private fun enforceSecureWindow() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    private fun securitySignals(): Map<String, Any> {
        val hookIndicators = hookIndicators()
        val rootIndicators = rootIndicators()
        val packageName = packageName
        val installer = installerPackageName() ?: ""
        return mapOf(
            "packageName" to packageName,
            "installerPackageName" to installer,
            "debuggable" to ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
            "debuggerConnected" to (Debug.isDebuggerConnected() || Debug.waitingForDebugger()),
            "rootIndicators" to rootIndicators,
            "hookIndicators" to hookIndicators,
            "signingCertificateSha256" to signingCertificateSha256(),
            "sourceDir" to (applicationInfo.sourceDir ?: ""),
            "publicSourceDir" to (applicationInfo.publicSourceDir ?: "")
        )
    }

    private fun installerPackageName(): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun signingCertificateSha256(): List<String> {
        return try {
            @Suppress("DEPRECATION")
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
            } else {
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            }

            @Suppress("DEPRECATION")
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signingInfo = packageInfo.signingInfo ?: return emptyList()
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
            } else {
                packageInfo.signatures
            }

            signatures
                .orEmpty()
                .map { sha256(it.toByteArray()) }
                .distinct()
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun sha256(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString(":") {
            String.format(Locale.US, "%02X", it.toInt() and 0xff)
        }
    }

    private fun rootIndicators(): List<String> {
        val paths = listOf(
            "/system/app/Superuser.apk",
            "/system/xbin/su",
            "/system/bin/su",
            "/system/bin/.ext/su",
            "/sbin/su",
            "/sbin/.magisk",
            "/data/adb/magisk",
            "/data/local/su",
            "/data/local/bin/su",
            "/data/local/xbin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/tmp/su",
            "/system/app/SuperSU.apk",
            "/system/xbin/busybox",
            "/cache/magisk.log"
        )
        return paths.filter { path ->
            try {
                File(path).exists()
            } catch (_: Throwable) {
                false
            }
        }
    }

    private fun hookIndicators(): List<String> {
        val indicators = linkedSetOf<String>()
        val keywords = listOf(
            "frida",
            "gum-js-loop",
            "gadget",
            "xposed",
            "edxposed",
            "lsposed",
            "zygisk",
            "riru",
            "substrate",
            "substrate-dvm",
            "objection",
            "reframework"
        )
        try {
            File("/proc/self/maps").useLines { lines ->
                lines.take(9000).forEach { line ->
                    val lower = line.lowercase(Locale.US)
                    for (keyword in keywords) {
                        if (lower.contains(keyword)) {
                            indicators += keyword
                        }
                    }
                }
            }
        } catch (_: Throwable) {
            // hardened kernels can deny maps access, so absence of this signal is not trusted
        }
        return indicators.toList()
    }
}
