import 'package:flutter/material.dart';
import '../../core/gns/identity_wallet.dart';
import '../gsite/gsite_creator.dart';  // 🐆 gSite Creator

/// Debug screen for manual GNS operations
/// 
/// Use this to manually trigger network operations like publishing your record.
/// Location: lib/screens/debug_screen.dart
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _wallet = IdentityWallet();
  bool _isPublishing = false;
  String? _statusMessage;
  Color _statusColor = Colors.grey;

  Future<void> _publishRecord() async {
    setState(() {
      _isPublishing = true;
      _statusMessage = 'Publishing record to network...';
      _statusColor = Colors.blue;
    });

    try {
      final success = await _wallet.publishToNetwork();
      
      setState(() {
        _isPublishing = false;
        if (success) {
          _statusMessage = '✅ Record published successfully!';
          _statusColor = Colors.green;
        } else {
          _statusMessage = '⚠️ Publish failed - check network connection';
          _statusColor = Colors.orange;
        }
      });
    } catch (e) {
      setState(() {
        _isPublishing = false;
        _statusMessage = '❌ Error: $e';
        _statusColor = Colors.red;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Tools'),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(  // 🐆 Added scroll for more content
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Identity Info Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Identity Info',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Public Key (Ed25519)', 
                        _wallet.publicKey?.substring(0, 16) ?? 'None'),
                      const SizedBox(height: 8),
                      _buildInfoRow('Encryption Key (X25519)', 
                        _wallet.encryptionPublicKeyHex?.substring(0, 16) ?? 'None'),
                      const SizedBox(height: 8),
                      _buildInfoRow('GNS ID', 
                        _wallet.gnsId ?? 'None'),
                      const SizedBox(height: 8),
                      _buildInfoRow('Network Available', 
                        _wallet.networkAvailable ? 'Yes ✅' : 'No ❌'),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Publish Record Button
              ElevatedButton.icon(
                onPressed: _isPublishing ? null : _publishRecord,
                icon: _isPublishing 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.upload),
                label: Text(
                  _isPublishing ? 'Publishing...' : 'Publish Record to Network',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Status Message
              if (_statusMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _statusColor),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              
              const SizedBox(height: 24),
              
              // Help Text
              const Card(
                color: Color(0xFFF5F5F5),
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 What does this do?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'This button publishes your GNS record (including your X25519 encryption key) to the network. This is needed so others can encrypt messages to you.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '🔑 Your record includes:\n'
                        '• Ed25519 public key (identity)\n'
                        '• X25519 public key (encryption)\n'
                        '• Handle (if claimed)\n'
                        '• Trust score & breadcrumbs',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              
              // ============================================================
              // 🐆 gSITE CREATOR - NEW SECTION
              // ============================================================
              
              const SizedBox(height: 24),
              
              const GSiteCreatorCard(),
              
              const SizedBox(height: 24),  // Bottom padding
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
