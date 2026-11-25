package ir.alishams.baladi.community

import android.content.Intent
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class BaladiCommunityWebView(godot: Godot) : GodotPlugin(godot) {
    init {
        activePlugin = this
    }

    override fun getPluginName(): String = "BaladiCommunityWebView"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("session_updated", String::class.java)
    )

    @UsedByGodot
    fun openCommunityChat(accessToken: String, refreshToken: String, expiresAt: Double, userJson: String) {
        runOnHostThread {
            val host = activity ?: return@runOnHostThread
            try {
                val intent = Intent(host, CommunityChatActivity::class.java).apply {
                    putExtra(CommunityChatActivity.EXTRA_ACCESS_TOKEN, accessToken)
                    putExtra(CommunityChatActivity.EXTRA_REFRESH_TOKEN, refreshToken)
                    putExtra(CommunityChatActivity.EXTRA_EXPIRES_AT, expiresAt.toLong())
                    putExtra(CommunityChatActivity.EXTRA_USER_JSON, userJson)
                }
                host.startActivity(intent)
            } catch (error: Throwable) {
                Log.e("BaladiCommunityChat", "Failed to launch community chat Activity", error)
            }
        }
    }

    fun forwardSessionToGodot(sessionJson: String) {
        activity?.runOnUiThread {
            emitSignal("session_updated", sessionJson)
        }
    }

    companion object {
        @Volatile
        var activePlugin: BaladiCommunityWebView? = null
    }
}
