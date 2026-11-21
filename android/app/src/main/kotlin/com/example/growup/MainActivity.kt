package com.example.growup

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.growup/backup"
    private val saveRequestCode = 5124
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveBackup") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("busy", "A backup save is already open.", null)
                    return@setMethodCallHandler
                }
                val fileName = call.argument<String>("fileName")
                val bytes = call.argument<ByteArray>("bytes")
                if (fileName.isNullOrBlank() || bytes == null) {
                    result.error("invalid", "Missing backup file data.", null)
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    putExtra(Intent.EXTRA_TITLE, fileName)
                }
                pendingResult = result
                pendingBytes = bytes
                try {
                    startActivityForResult(intent, saveRequestCode)
                } catch (error: Exception) {
                    pendingResult = null
                    pendingBytes = null
                    result.error("save_unavailable", error.message, null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequestCode) return
        val result = pendingResult ?: return
        val bytes = pendingBytes
        pendingResult = null
        pendingBytes = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(false)
            return
        }
        try {
            val output = contentResolver.openOutputStream(data.data!!, "w")
                ?: throw IllegalStateException("Could not open backup destination.")
            output.use { it.write(bytes ?: throw IllegalStateException("Missing backup data.")) }
            result.success(true)
        } catch (error: Exception) {
            result.error("save_failed", error.message, null)
        }
    }
}
