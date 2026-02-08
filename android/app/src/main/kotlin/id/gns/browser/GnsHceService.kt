package id.gns.browser

import android.content.Intent
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Arrays

/**
 * GNS Host Card Emulation Service
 * 
 * Handles NFC card emulation for tap-to-pay functionality.
 * Communicates with Flutter via platform channels.
 */
class GnsHceService : HostApduService() {
    
    companion object {
        private const val TAG = "GnsHce"
        
        // ISO-DEP / ISO 7816-4 Commands
        private const val SELECT_INS: Byte = 0xA4.toByte()
        private const val GET_DATA_INS: Byte = 0xCA.toByte()
        private const val PUT_DATA_INS: Byte = 0xDA.toByte()
        
        // Status words
        private val SW_OK = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_UNKNOWN = byteArrayOf(0x6F.toByte(), 0x00)
        private val SW_FILE_NOT_FOUND = byteArrayOf(0x6A.toByte(), 0x82.toByte())
        private val SW_WRONG_LENGTH = byteArrayOf(0x67.toByte(), 0x00)
        
        // GNS Application ID (AID)
        // Format: F0 47 4E 53 50 41 59 = "GNSPAY" with RID prefix
        val GNS_AID = byteArrayOf(
            0xF0.toByte(), // Proprietary RID
            0x47, 0x4E, 0x53, // "GNS"
            0x50, 0x41, 0x59  // "PAY"
        )
        
        // Singleton event sink for Flutter communication
        var eventSink: EventChannel.EventSink? = null
        var pendingResponse: ByteArray? = null
    }
    
    private var isSelected = false
    
    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        Log.d(TAG, "APDU received: ${commandApdu.toHexString()}")
        
        if (commandApdu.size < 4) {
            return SW_WRONG_LENGTH
        }
        
        val cla = commandApdu[0]
        val ins = commandApdu[1]
        val p1 = commandApdu[2]
        val p2 = commandApdu[3]
        
        return when (ins) {
            SELECT_INS -> handleSelect(commandApdu)
            GET_DATA_INS -> handleGetData(commandApdu)
            PUT_DATA_INS -> handlePutData(commandApdu)
            else -> {
                Log.d(TAG, "Unknown instruction: ${ins.toHexString()}")
                SW_UNKNOWN
            }
        }
    }
    
    override fun onDeactivated(reason: Int) {
        Log.d(TAG, "HCE Deactivated: reason=$reason")
        isSelected = false
        
        // Notify Flutter
        eventSink?.success(mapOf(
            "type" to "deactivated",
            "reason" to when (reason) {
                DEACTIVATION_LINK_LOSS -> "link_loss"
                DEACTIVATION_DESELECTED -> "deselected"
                else -> "unknown"
            }
        ))
    }
    
    /**
     * Handle SELECT command
     * 
     * Command: 00 A4 04 00 Lc [AID] Le
     * Response: [Application Data] 90 00
     */
    private fun handleSelect(apdu: ByteArray): ByteArray {
        if (apdu.size < 5) {
            return SW_WRONG_LENGTH
        }
        
        val lc = apdu[4].toInt() and 0xFF
        if (apdu.size < 5 + lc) {
            return SW_WRONG_LENGTH
        }
        
        val aid = apdu.copyOfRange(5, 5 + lc)
        
        if (Arrays.equals(aid, GNS_AID)) {
            Log.d(TAG, "GNS application selected")
            isSelected = true
            
            // Return application info + OK
            val appInfo = buildApplicationInfo()
            return appInfo + SW_OK
        }
        
        Log.d(TAG, "Unknown AID: ${aid.toHexString()}")
        return SW_FILE_NOT_FOUND
    }
    
    /**
     * Handle GET DATA command (read payment challenge from phone)
     * 
     * Used by merchant terminal to read user's response
     */
    private fun handleGetData(apdu: ByteArray): ByteArray {
        if (!isSelected) {
            return SW_FILE_NOT_FOUND
        }
        
        // Check if we have a pending response from Flutter
        val response = pendingResponse
        if (response != null) {
            pendingResponse = null
            return response + SW_OK
        }
        
        // No data available
        return SW_FILE_NOT_FOUND
    }
    
    /**
     * Handle PUT DATA command (receive payment challenge from terminal)
     * 
     * Used by merchant terminal to send payment request
     */
    private fun handlePutData(apdu: ByteArray): ByteArray {
        if (!isSelected) {
            return SW_FILE_NOT_FOUND
        }
        
        if (apdu.size < 5) {
            return SW_WRONG_LENGTH
        }
        
        val lc = apdu[4].toInt() and 0xFF
        if (apdu.size < 5 + lc) {
            return SW_WRONG_LENGTH
        }
        
        val data = apdu.copyOfRange(5, 5 + lc)
        
        // Forward to Flutter for processing
        eventSink?.success(mapOf(
            "type" to "apdu_received",
            "data" to data
        ))
        
        return SW_OK
    }
    
    /**
     * Build application information response
     */
    private fun buildApplicationInfo(): ByteArray {
        // TLV structure for GNS payment application
        // Tag 6F (FCI Template)
        //   Tag 84 (DF Name/AID)
        //   Tag A5 (FCI Proprietary Template)
        //     Tag 50 (Application Label)
        //     Tag 9F38 (PDOL - Processing Options Data Object List)
        
        val appLabel = "GNS Pay".toByteArray(Charsets.UTF_8)
        
        return byteArrayOf(
            0x6F.toByte(), // FCI Template tag
            (4 + GNS_AID.size + 4 + appLabel.size).toByte(), // Length
            
            0x84.toByte(), // AID tag
            GNS_AID.size.toByte(),
            *GNS_AID,
            
            0xA5.toByte(), // FCI Proprietary Template tag
            (2 + appLabel.size).toByte(),
            
            0x50.toByte(), // Application Label tag
            appLabel.size.toByte(),
            *appLabel
        )
    }
    
    // Extension functions for hex conversion
    private fun ByteArray.toHexString(): String = 
        joinToString("") { "%02X".format(it) }
    
    private fun Byte.toHexString(): String = 
        "%02X".format(this)
}

/**
 * Flutter method channel handler for HCE
 */
class GnsHceMethodHandler(private val context: android.content.Context) : MethodChannel.MethodCallHandler {
    
    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enableHce" -> {
                // HCE is automatically enabled when service is registered in manifest
                result.success(true)
            }
            "disableHce" -> {
                result.success(true)
            }
            "sendResponse" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    GnsHceService.pendingResponse = data
                    result.success(true)
                } else {
                    result.error("INVALID_DATA", "No data provided", null)
                }
            }
            "isHceSupported" -> {
                val pm = context.packageManager
                val hasNfc = pm.hasSystemFeature(android.content.pm.PackageManager.FEATURE_NFC)
                val hasHce = pm.hasSystemFeature(android.content.pm.PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)
                result.success(hasNfc && hasHce)
            }
            else -> result.notImplemented()
        }
    }
}

/**
 * Flutter event channel stream handler for HCE events
 */
class GnsHceEventHandler : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        GnsHceService.eventSink = events
    }
    
    override fun onCancel(arguments: Any?) {
        GnsHceService.eventSink = null
    }
}
