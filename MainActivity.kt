package com.btcmorning.btcmarketpro

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.btcmorning.btcmarketpro/permissions"
    private val NOTIF_REQUEST_CODE = 1001

    /**
     * Startup fazı flag'i.
     * true  → uygulama henüz yükleniyor, kamera/mikrofon dialog'u engellenir
     * false → kullanıcı uygulama içinde gerçekten izin isteyebilir
     *
     * İki şekilde false yapılır:
     *   1. Dart tarafı "setAppReady" channel çağrısı (WebView onLoadStop)
     *   2. Fallback: 5 saniye sonra otomatik
     */
    @Volatile
    private var startupBlocked = true

    private val startupHandler = Handler(Looper.getMainLooper())

    // Startup'ta engellenmesi gereken izinler
    private val STARTUP_BLOCKED_PERMS = setOf(
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO
    )

    // ----------------------------------------------------------------
    // Lifecycle
    // ----------------------------------------------------------------

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        WebView.setWebContentsDebuggingEnabled(false)

        // Bildirim iznini hemen iste (bu normal, startup'ta sorun değil)
        requestNotificationPermission()

        // Fallback: Dart "setAppReady" çağırmazsa 5 saniye sonra engeli kaldır
        startupHandler.postDelayed({
            startupBlocked = false
        }, 5000)
    }

    override fun onDestroy() {
        super.onDestroy()
        startupHandler.removeCallbacksAndMessages(null)
    }

    // ----------------------------------------------------------------
    // Permission intercept — Activity seviyesi (tüm plugin'lar buraya gelir)
    // ----------------------------------------------------------------

    override fun requestPermissions(permissions: Array<String>, requestCode: Int) {
        if (startupBlocked && permissions.any { it in STARTUP_BLOCKED_PERMS }) {
            // Startup fazında kamera/mikrofon dialog'unu gösterme
            // Sisteme "reddedildi" olarak bildir, uygulama çökmez
            onRequestPermissionsResult(
                requestCode,
                permissions,
                IntArray(permissions.size) { i ->
                    if (permissions[i] in STARTUP_BLOCKED_PERMS)
                        PackageManager.PERMISSION_DENIED
                    else
                        PackageManager.PERMISSION_GRANTED
                }
            )
            return
        }
        super.requestPermissions(permissions, requestCode)
    }

    // PluginRegistry callback'li versiyon (bazı eski flutter plugin'ları kullanır)
    override fun requestPermissions(
        permissions: Array<String>,
        requestCode: Int,
        resultCallback: PluginRegistry.RequestPermissionsResultListener
    ) {
        if (startupBlocked && permissions.any { it in STARTUP_BLOCKED_PERMS }) {
            resultCallback.onRequestPermissionsResult(
                requestCode,
                permissions,
                IntArray(permissions.size) { i ->
                    if (permissions[i] in STARTUP_BLOCKED_PERMS)
                        PackageManager.PERMISSION_DENIED
                    else
                        PackageManager.PERMISSION_GRANTED
                }
            )
            return
        }
        super.requestPermissions(permissions, requestCode, resultCallback)
    }

    // ----------------------------------------------------------------
    // Flutter Method Channel
    // ----------------------------------------------------------------

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // WebView yükleme tamamlandığında Dart bu metodu çağırır
                    // → Artık kullanıcı kamera/fotoğraf kullanabilir, dialog çıkabilir
                    "setAppReady" -> {
                        startupBlocked = false
                        startupHandler.removeCallbacksAndMessages(null)
                        result.success(true)
                    }

                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(true)
                    }

                    "checkNotificationPermission" -> {
                        result.success(hasNotificationPermission())
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ----------------------------------------------------------------
    // Notification helpers
    // ----------------------------------------------------------------

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!hasNotificationPermission()) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIF_REQUEST_CODE
                )
            }
        }
    }

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else true
    }
}
