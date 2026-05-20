package com.btcmorning.btcmarketpro

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebView

/**
 * WebView kamera/mikrofon erişimini tamamen kapatan yardımcı sınıf.
 * flutter_inappwebview plugin'ini bypass etmeden önce çalışır.
 */
object CameraBlocker {

    fun apply(context: Context) {
        try {
            // WebView'ın kamera/mikrofon için izin istemesini engelle
            val wv = WebView(context)
            wv.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest?) {
                    request?.deny()
                }
            }
            wv.destroy()
        } catch (_: Exception) {}
    }

    /**
     * Context'e sarılarak checkSelfPermission/checkPermission'ı override eder.
     * flutter_inappwebview bu context üzerinden izin kontrolü yapar.
     */
    fun wrap(context: Context): Context {
        return BlockingContext(context)
    }

    private val BLOCKED = setOf(
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO,
        "android.permission.CAMERA",
        "android.permission.RECORD_AUDIO"
    )

    fun isBlocked(permission: String) = permission in BLOCKED
}

class BlockingContext(base: Context) : android.content.ContextWrapper(base) {
    private val BLOCKED = setOf(
        Manifest.permission.CAMERA,
        Manifest.permission.RECORD_AUDIO
    )

    override fun checkSelfPermission(permission: String): Int {
        if (permission in BLOCKED) return PackageManager.PERMISSION_DENIED
        return super.checkSelfPermission(permission)
    }

    override fun checkPermission(permission: String, pid: Int, uid: Int): Int {
        if (permission in BLOCKED) return PackageManager.PERMISSION_DENIED
        return super.checkPermission(permission, pid, uid)
    }
}