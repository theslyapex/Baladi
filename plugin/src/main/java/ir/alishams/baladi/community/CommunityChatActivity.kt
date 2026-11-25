package ir.alishams.baladi.community

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.util.Log
import android.widget.TextView
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject

class CommunityChatActivity : Activity() {
    private lateinit var webView: WebView
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var pendingWebPermission: PermissionRequest? = null
    private var permissionRequestInFlight = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            initializeCommunityChat()
        } catch (error: Throwable) {
            Log.e(TAG, "Community chat Activity initialization failed", error)
            try {
                val fallback = TextView(this).apply {
                    text = "باز کردن انجمن گفت‌وگو با خطا مواجه شد.\\n\\nنوع خطا: ${error.javaClass.simpleName}\\nجزئیات: ${error.message ?: "بدون توضیح"}\\n\\nاز این صفحه عکس بگیر و برای پشتیبانی بفرست."
                    textSize = 16f
                    setTextColor(android.graphics.Color.WHITE)
                    setBackgroundColor(android.graphics.Color.rgb(12, 16, 11))
                    gravity = android.view.Gravity.CENTER
                    setPadding(32, 32, 32, 32)
                }
                setContentView(fallback)
            } catch (fallbackError: Throwable) {
                Log.e(TAG, "Community chat fallback view failed", fallbackError)
                finish()
            }
        }
    }

    private fun initializeCommunityChat() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        )
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )

        webView = WebView(this)
        webView.setBackgroundColor(android.graphics.Color.rgb(12, 16, 11))
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.mediaPlaybackRequiresUserGesture = false
        webView.settings.allowFileAccess = false
        webView.settings.allowContentAccess = true
        webView.settings.javaScriptCanOpenWindowsAutomatically = false
        webView.addJavascriptInterface(SessionBridge(), "BaladiCommunityBridge")

        val root = FrameLayout(this)
        root.addView(webView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))
        setContentView(root)

        val accessToken = intent.getStringExtra(EXTRA_ACCESS_TOKEN).orEmpty()
        val refreshToken = intent.getStringExtra(EXTRA_REFRESH_TOKEN).orEmpty()
        val expiresAt = intent.getLongExtra(EXTRA_EXPIRES_AT, 0L)
        val userJson = intent.getStringExtra(EXTRA_USER_JSON).orEmpty()
        val bootstrapHtml = buildSessionBootstrapHtml(accessToken, refreshToken, expiresAt, userJson)

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val uri = request?.url ?: return false
                val host = uri.host.orEmpty().lowercase()
                if (host == "alishams.ir" || host == "www.alishams.ir") return false
                return try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    true
                } catch (_: Exception) {
                    true
                }
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                view: WebView?,
                callback: ValueCallback<Array<Uri>>?,
                params: FileChooserParams?
            ): Boolean {
                fileCallback?.onReceiveValue(null)
                fileCallback = callback
                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                        "image/*", "video/mp4", "video/webm", "audio/*",
                        "application/pdf", "application/zip",
                        "application/msword",
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                        "application/vnd.ms-excel",
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                        "text/plain"
                    ))
                }
                return try {
                    startActivityForResult(intent, REQUEST_FILE)
                    true
                } catch (_: Exception) {
                    fileCallback = null
                    false
                }
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                if (request == null) return
                val wantsAudio = request.resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)
                if (!wantsAudio) {
                    request.deny()
                    return
                }
                if (ContextCompat.checkSelfPermission(this@CommunityChatActivity, Manifest.permission.RECORD_AUDIO)
                    == PackageManager.PERMISSION_GRANTED
                ) {
                    runOnUiThread { request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) }
                } else if (!permissionRequestInFlight) {
                    pendingWebPermission = request
                    permissionRequestInFlight = true
                    ActivityCompat.requestPermissions(
                        this@CommunityChatActivity,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        REQUEST_AUDIO
                    )
                } else {
                    request.deny()
                }
            }
        }

        if (bootstrapHtml != null) {
            webView.loadDataWithBaseURL("https://alishams.ir/", bootstrapHtml, "text/html", "UTF-8", null)
        } else {
            webView.loadUrl(CHAT_URL)
        }
    }

    private fun buildSessionBootstrapHtml(
        accessToken: String,
        refreshToken: String,
        expiresAt: Long,
        userJson: String
    ): String? {
        if (accessToken.isBlank() || refreshToken.isBlank() || userJson.isBlank()) return null
        return try {
            val user = JSONObject(userJson)
            val session = JSONObject()
                .put("access_token", accessToken)
                .put("refresh_token", refreshToken)
                .put("expires_at", expiresAt)
                .put("expires_in", (expiresAt - System.currentTimeMillis() / 1000L).coerceAtLeast(1L))
                .put("token_type", "bearer")
                .put("user", user)
            val key = JSONObject.quote(AUTH_STORAGE_KEY)
            val value = JSONObject.quote(session.toString())
            """
                <!doctype html>
                <html><head><meta charset="utf-8"></head>
                <body><script>
                  (function () {
                    try {
                      localStorage.setItem($key, $value);
                      sessionStorage.setItem("__baladiSessionSeeded", "1");
                    } catch (e) {}
                    const originalSetItem = Storage.prototype.setItem;
                    Storage.prototype.setItem = function (name, value) {
                      originalSetItem.call(this, name, value);
                      if (name === $key && window.BaladiCommunityBridge) {
                        try { window.BaladiCommunityBridge.onSessionChanged(value); } catch (e) {}
                      }
                    };
                    window.location.replace("$CHAT_URL");
                  })();
                </script></body></html>
            """.trimIndent()
        } catch (error: Exception) {
            Log.e(TAG, "Could not create community session bootstrap", error)
            null
        }
    }

    inner class SessionBridge {
        @JavascriptInterface
        fun onSessionChanged(value: String) {
            try {
                BaladiCommunityWebView.activePlugin?.forwardSessionToGodot(value)
            } catch (_: Exception) {
                // Ignore malformed or unavailable bridge updates.
            }
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) webView.goBack()
        else finish()
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_FILE) {
            val result = if (resultCode == Activity.RESULT_OK && data?.data != null) arrayOf(data.data!!) else null
            fileCallback?.onReceiveValue(result)
            fileCallback = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_AUDIO) return
        permissionRequestInFlight = false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        val pending = pendingWebPermission
        pendingWebPermission = null
        if (granted) pending?.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
        else pending?.deny()
    }

    override fun onDestroy() {
        fileCallback?.onReceiveValue(null)
        fileCallback = null
        pendingWebPermission?.deny()
        pendingWebPermission = null
        if (::webView.isInitialized) {
            try {
                webView.stopLoading()
                webView.loadUrl("about:blank")
                webView.destroy()
            } catch (error: Throwable) {
                Log.e(TAG, "WebView cleanup failed", error)
            }
        }
        super.onDestroy()
    }

    companion object {
        private const val TAG = "BaladiCommunityChat"
        const val CHAT_URL = "https://alishams.ir/community-chat.html"
        const val EXTRA_ACCESS_TOKEN = "community_access_token"
        const val EXTRA_REFRESH_TOKEN = "community_refresh_token"
        const val EXTRA_EXPIRES_AT = "community_expires_at"
        const val EXTRA_USER_JSON = "community_user_json"
        const val REQUEST_FILE = 0xCA71
        const val REQUEST_AUDIO = 0xCA72
        const val AUTH_STORAGE_KEY = "sb-srfldjfrzmtnlabusssq-auth-token"
    }
}
