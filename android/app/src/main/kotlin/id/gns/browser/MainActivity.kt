package id.gns.browser

import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    private var nfcAdapter: NfcAdapter? = null
    
    companion object {
        private const val NFC_CHANNEL = "gns.id/nfc"
        private const val HCE_CHANNEL = "gns.id/nfc_hce"
        private const val HCE_EVENTS = "gns.id/nfc_hce_events"
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // NFC Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NFC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNfcAvailable" -> {
                        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
                        result.success(nfcAdapter != null)
                    }
                    "isNfcEnabled" -> {
                        result.success(nfcAdapter?.isEnabled == true)
                    }
                    else -> result.notImplemented()
                }
            }
        
        // HCE Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HCE_CHANNEL)
            .setMethodCallHandler(GnsHceMethodHandler(this))
        
        // HCE Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HCE_EVENTS)
            .setStreamHandler(GnsHceEventHandler())
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        handleIntent(intent)
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }
    
    private fun handleIntent(intent: Intent) {
        when (intent.action) {
            NfcAdapter.ACTION_NDEF_DISCOVERED,
            NfcAdapter.ACTION_TECH_DISCOVERED,
            NfcAdapter.ACTION_TAG_DISCOVERED -> {
                val tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
                // Forward to Flutter via method channel
            }
        }
    }
}
