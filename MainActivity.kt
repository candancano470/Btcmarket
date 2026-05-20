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

    // CAMERA her zaman DENIED döner — plugin izin istemez
    override fun checkSelfPermission(permission: String): Int {
        if (permission in BLOCKED) return PackageManager.PERMISSION_DENIED
        return super.checkSelfPermission(permission)
    }

    override fun checkPermission(permission: String, pid: Int, uid: Int): Int {
        if (permission in BLOCKED) return PackageManager.PERMISSION_DENIED
        return super.checkPermission(permission, pid, uid)
    }

    // ActivityResultLauncher tabanlı istekleri yakala (flutter_inappwebview 6.x)
    private val blockedRegistry: ActivityResultRegistry by lazy {
        object : ActivityResultRegistry() {
            override fun <I, O> onLaunch(
                requestCode: Int,
                contract: androidx.activity.result.contract.ActivityResultContract<I, O>,
                input: I,
                options: androidx.core.app.ActivityOptionsCompat?
            ) {
                if (contract is ActivityResultContracts.RequestMultiplePermissions) {
                    @Suppress("UNCHECKED_CAST")
                    val perms = input as? Array<String> ?: emptyArray()
                    if (perms.any { it in BLOCKED }) {
                        val result = perms.associateWith { it !in BLOCKED }
                        @Suppress("UNCHECKED_CAST")
                        dispatchResult(requestCode, result as O)
                        return
                    }
                } else if (contract is ActivityResultContracts.RequestPermission) {
                    val perm = input as? String
                    if (perm != null && perm in BLOCKED) {
                        @Suppress("UNCHECKED_CAST")
                        dispatchResult(requestCode, false as O)
                        return
                    }
                }
                super.onLaunch(requestCode, contract, input, options)
            }
        }
    }

    override fun getActivityResultRegistry(): ActivityResultRegistry = blockedRegistry

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
        val sanitized = grantResults.copyOf()
        for (i in permissions.indices) {
            if (permissions[i] in BLOCKED) {
                sanitized[i] = PackageManager.PERMISSION_DENIED
            }
        }
        super.onRequestPermissionsResult(requestCode, permissions, sanitized)
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