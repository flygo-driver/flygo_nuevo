package com.flygo.rd2

import android.os.Bundle
import androidx.core.view.WindowCompat
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.flygo.rd2/negocio_referido"
    private var cachedReferrer: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstallReferrer" -> {
                        if (cachedReferrer != null) {
                            result.success(cachedReferrer)
                            return@setMethodCallHandler
                        }
                        val client = InstallReferrerClient.newBuilder(this).build()
                        client.startConnection(object : InstallReferrerStateListener {
                            override fun onInstallReferrerSetupFinished(code: Int) {
                                try {
                                    if (code == InstallReferrerClient.InstallReferrerResponse.OK) {
                                        cachedReferrer = client.installReferrer.installReferrer
                                    }
                                } catch (_: Exception) {
                                } finally {
                                    client.endConnection()
                                    result.success(cachedReferrer ?: "")
                                }
                            }

                            override fun onInstallReferrerServiceDisconnected() {
                                result.success(cachedReferrer ?: "")
                            }
                        })
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
