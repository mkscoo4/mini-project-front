// android/app/src/main/kotlin/com/example/koscom_test1/MainActivity.kt

package com.example.koscom_test1

import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.koscom_test1/mms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMmsText" -> {
                        val mmsId = call.argument<String>("mmsId")
                        if (mmsId == null) {
                            result.error("INVALID_ARGUMENT", "MMS id is null", null)
                            return@setMethodCallHandler
                        }
                        val text = getMmsText(mmsId)
                        if (text != null) {
                            result.success(text)
                        } else {
                            result.error("UNAVAILABLE", "MMS text not found", null)
                        }
                    }
                    "getLatestMms" -> {
                        // getLatestMms()에서 최신 MMS 정보를 Map으로 반환합니다.
                        val mmsInfo = getLatestMms()
                        if (mmsInfo != null) {
                            result.success(mmsInfo)
                        } else {
                            // 최신 MMS가 없으면 빈 Map 또는 null 반환
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * MMS의 파트 테이블(content://mms/part)에서
     * 주어진 MMS ID에 해당하는 텍스트 파트를 추출합니다.
     */
    private fun getMmsText(mmsId: String): String? {
        val uri = Uri.parse("content://mms/part")
        val selection = "mid=?"
        val selectionArgs = arrayOf(mmsId)
        var mmsText: String? = null

        val cursor: Cursor? = contentResolver.query(uri, null, selection, selectionArgs, null)
        cursor?.use {
            while (it.moveToNext()) {
                val ct = it.getString(it.getColumnIndex("ct"))
                if (ct.equals("text/plain", ignoreCase = true)) {
                    // _data 컬럼이 있으면 파일에서 텍스트를 읽어옵니다.
                    val data = it.getString(it.getColumnIndex("_data"))
                    mmsText = if (data != null) {
                        val partId = it.getString(it.getColumnIndex("_id"))
                        val partUri = Uri.parse("content://mms/part/$partId")
                        readDataFromUri(partUri)
                    } else {
                        // _data가 없는 경우 text 컬럼에 텍스트가 있음
                        it.getString(it.getColumnIndex("text"))
                    }
                    break
                }
            }
        }
        return mmsText
    }

    /**
     * 주어진 URI에서 텍스트 데이터를 읽어 문자열로 반환합니다.
     */
    private fun readDataFromUri(uri: Uri): String? {
        return try {
            contentResolver.openInputStream(uri)?.use { inputStream ->
                BufferedReader(InputStreamReader(inputStream)).use { reader ->
                    val builder = StringBuilder()
                    var line: String? = reader.readLine()
                    while (line != null) {
                        builder.append(line)
                        line = reader.readLine()
                    }
                    builder.toString()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    /**
     * 최신 수신 MMS의 정보를 조회합니다.
     *
     * 이 메소드는 수신함(content://mms/inbox)에서 최신 MMS를 조회하고,
     * 해당 MMS의 ID, 수신 시각(date) 및 발신자(address)를 포함한 Map을 반환합니다.
     *
     * 반환 Map의 예시:
     * {
     *    "id": "12345",
     *    "address": "+821012345678",
     *    "timestamp": 1670000000000
     * }
     *
     * 발신자 정보는 별도의 주소 테이블(content://mms/{id}/addr)에서 type=137 (발신자)인 값을 가져옵니다.
     */
    private fun getLatestMms(): Map<String, Any>? {
        // 수신 MMS가 저장된 URI (수신함)
        val mmsInboxUri = Uri.parse("content://mms/inbox")
        // 최신 MMS 하나를 가져오기 위해 date 내림차순 정렬
        val projection = arrayOf("_id", "date")
        val sortOrder = "date DESC"
        val cursor: Cursor? = contentResolver.query(mmsInboxUri, projection, null, null, sortOrder)

        cursor?.use {
            if (it.moveToFirst()) {
                val mmsId = it.getString(it.getColumnIndex("_id"))
                // date는 초 단위이므로 밀리초로 변환 (곱하기 1000)
                val dateSeconds = it.getLong(it.getColumnIndex("date"))
                val timestamp = dateSeconds * 1000

                // 발신자 정보는 주소 테이블에서 조회 (type=137: From)
                val address = getMmsAddress(mmsId) ?: "Unknown"

                // 최신 MMS 정보를 Map에 담아 반환합니다.
                return mapOf(
                    "id" to mmsId,
                    "address" to address,
                    "timestamp" to timestamp
                )
            }
        }
        return null
    }

    /**
     * 주어진 MMS ID에 대해, 해당 MMS의 주소 테이블(content://mms/{mmsId}/addr)에서
     * type=137(발신자)에 해당하는 주소 값을 가져옵니다.
     */
    private fun getMmsAddress(mmsId: String): String? {
        val addrUri = Uri.parse("content://mms/$mmsId/addr")
        val projection = arrayOf("address", "type")
        val selection = "type=137"  // 137: From
        val cursor: Cursor? = contentResolver.query(addrUri, projection, selection, null, null)
        cursor?.use {
            if (it.moveToFirst()) {
                val address = it.getString(it.getColumnIndex("address"))
                return address
            }
        }
        return null
    }
}
