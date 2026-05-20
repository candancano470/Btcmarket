package com.btcmorning.btcmarketpro

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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

    private val BLOCKED = setOf(
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        WebView.setWebContentsDebuggingEnabled(false)
        requestNotificationPermission()
    }

    override fun requestPermissions(
        permissions: Array<String>,
        requestCode: Int,
        resultCallback: PluginRegistry.RequestPermissionsResultListener
    ) {
        val filtered = permissions.filter { it !in BLOCKED }.toTypedArray()
        if (filtered.isEmpty()) {
            resultCallback.onRequestPermissionsResult(
                requestCode,
                permissions,
                IntArray(permissions.size) { PackageManager.PERMISSION_DENIED }
            )
            return
        }
        super.requestPermissions(filtered, requestCode, resultCallback)
    }

    override fun requestPermissions(permissions: Array<String>, requestCode: Int) {
        val filtered = permissions.filter { it !in BLOCKED }.toTypedArray()
        if (filtered.isEmpty()) {
            onRequestPermissionsResult(
                requestCode,
                permissions,
                IntArray(permissions.size) { PackageManager.PERMISSION_DENIED }
            )
            return
        }
        super.requestPermissions(filtered, requestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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