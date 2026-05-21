package com.btcmorning.btcmarketpro

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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

    @Volatile
    private var startupBlocked = true

    private val startupHandler = Handler(Looper.getMainLooper())

    private val STARTUP_BLOCKED_PERMS = setOf(
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO
    )

    private val lazyRegistry: ActivityResultRegistry by lazy {
        object : ActivityResultRegistry() {
            override fun <I, O> onLaunch(
                requestCode: Int,
                contract: androidx.activity.result.contract.ActivityResultContract<I, O>,
                input: I,
                options: ActivityOptionsCompat?
            ) {
                if (startupBlocked) {
                    when (contract) {
                        is ActivityResultContracts.RequestMultiplePermissions -> {
                            @Suppress("UNCHECKED_CAST")
                            val perms = input as? Array<String> ?: emptyArray()
                            if (perms.any { it in STARTUP_BLOCKED_PERMS }) {
                                val result = perms.associateWith { it !in STARTUP_BLOCKED_PERMS }
                                @Suppress("UNCHECKED_CAST")
                                dispatchResult(requestCode, result as O)
                                return
                            }
                        }
                        is ActivityResultContracts.RequestPermission -> {
                            val perm = input as? String
                            if (perm != null && perm in STARTUP_BLOCKED_PERMS) {
                                @Suppress("UNCHECKED_CAST")
                                dispatchResult(requestCode, false as O)
                                return
                            }
                        }
                    }
                }
                super.onLaunch(requestCode, contract, input, options)
            }
        }
    }

    override fun getActivityResultRegistry(): ActivityResultRegistry = lazyRegistry

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        WebView.setWebContentsDebuggingEnabled(false)
        requestNotificationPermission()

        startupHandler.postDelayed({
            startupBlocked = false
        }, 5000)
    }

    override fun onDestroy() {
        super.onDestroy()
        startupHandler.removeCallbacksAndMessages(null)
    }

    override fun requestPermissions(permissions: Array<String>, requestCode: Int) {
        if (startupBlocked && permissions.any { it in STARTUP_BLOCKED_PERMS }) {
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
