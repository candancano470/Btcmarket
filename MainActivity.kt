package com.btcmorning.btcmarketpro

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.webkit.WebView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.btcmorning.btcmarketpro/permissions"
    private val CAMERA_REQUEST = 1002
    private val NOTIF_REQUEST  = 1003

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WebView.setWebContentsDebuggingEnabled(false)
        // Açılışta HİÇBİR izin istenmez
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // Kullanıcı kamera seçtiğinde çağrılır
                    "allowCamera" -> {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                            != PackageManager.PERMISSION_GRANTED
                        ) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.CAMERA),
                                CAMERA_REQUEST
                            )
                        }
                        result.success(true)
                    }

                    // Kamera işlemi bitti
                    "blockCamera" -> {
                        result.success(true)
                    }

                    // WebView yüklendi — bildirim iznini şimdi sor
                    "setAppReady" -> {
                        requestNotificationPermission()
                        result.success(true)
                    }

                    // main.dart'tan çağrılır ama setAppReady ile handle ediliyor
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
                    NOTIF_REQUEST
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