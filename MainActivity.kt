package com.btcmorning.btcmarketpro

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.app.ActivityOptionsCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.btcmorning.btcmarketpro/permissions"
    private val NOTIF_REQUEST_CODE = 1001

    // Bu izinler HİÇBİR ZAMAN verilmez — ne startup'ta ne sonrasında
    private val ALWAYS_DENIED = setOf(
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO,
        Manifest.permission.MODIFY_AUDIO_SETTINGS
    )

    // ── Yeni Activity Result API yolunu bloke eder (flutter_inappwebview bunu kullanır) ──
    private val blockedRegistry = object : ActivityResultRegistry() {
        override fun <I, O> onLaunch(
            requestCode: Int,
            contract: androidx.activity.result.contract.ActivityResultContract<I, O>,
            input: I,
            options: ActivityOptionsCompat?
        ) {
            when (contract) {
                is ActivityResultContracts.RequestPermission -> {
                    val perm = input as? String
                    if (perm != null && perm in ALWAYS_DENIED) {
                        @Suppress("UNCHECKED_CAST")
                        dispatchResult(requestCode, false as O)
                        return
                    }
                }
                is ActivityResultContracts.RequestMultiplePermissions -> {
                    @Suppress("UNCHECKED_CAST")
                    val perms = input as? Array<String> ?: emptyArray()
                    if (perms.any { it in ALWAYS_DENIED }) {
                        val result = perms.associateWith { it !in ALWAYS_DENIED }
                        @Suppress("UNCHECKED_CAST")
                        dispatchResult(requestCode, result as O)
                        return
                    }
                }
            }
            super.onLaunch(requestCode, contract, input, options)
        }
    }

    override fun getActivityResultRegistry(): ActivityResultRegistry = blockedRegistry

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        WebView.setWebContentsDebuggingEnabled(false)
        requestNotificationPermission()
    }

    // ── Eski requestPermissions API yolunu bloke eder ──
    override fun requestPermissions(permissions: Array<String>, requestCode: Int) {
        if (permissions.any { it in ALWAYS_DENIED }) {
            onRequestPermissionsResult(
                requestCode,
                permissions,
                IntArray(permissions.size) { i ->
                    if (permissions[i] in ALWAYS_DENIED)
                        PackageManager.PERMISSION_DENIED
                    else
                        PackageManager.PERMISSION_GRANTED
                }
            )
            return
        }
        super.requestPermissions(permissions, requestCode)
    }

    // ── Flutter plugin registry API yolunu bloke eder ──
    override fun requestPermissions(
        permissions: Array<String>,
        requestCode: Int,
        resultCallback: PluginRegistry.RequestPermissionsResultListener
    ) {
        if (permissions.any { it in ALWAYS_DENIED }) {
            resultCallback.onRequestPermissionsResult(
                requestCode,
                permissions,
                IntArray(permissions.size) { i ->
                    if (permissions[i] in ALWAYS_DENIED)
                        PackageManager.PERMISSION_DENIED
                    else
                        PackageManager.PERMISSION_GRANTED
                }
            )
            return
        }
        super.requestPermissions(permissions, requestCode, resultCallback)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAppReady"                  -> result.success(true)
                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(true)
                    }
                    "checkNotificationPermission"  -> result.success(hasNotificationPermission())
                    else                           -> result.notImplemented()
                }
            }
    }

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
