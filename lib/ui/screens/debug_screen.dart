import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../gsite/gsite_creator.dart';  // 🐆 gSite Creator

/// Debug screen for GNS developer tools
/// 
/// Shows identity info and gSite creator.
/// Location: lib/ui/screens/debug_screen.dart
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _wallet = IdentityWallet();

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied!'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Tools'),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
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
                      _buildInfoRow(
                        'Public Key (Ed25519)', 
                        _wallet.publicKey?.substring(0, 16) ?? 'None',
                        fullValue: _wallet.publicKey,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Encryption Key (X25519)', 
                        _wallet.encryptionPublicKeyHex?.substring(0, 16) ?? 'None',
                        fullValue: _wallet.encryptionPublicKeyHex,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'GNS ID', 
                        _wallet.gnsId ?? 'None',
                        fullValue: _wallet.gnsId,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Network Available', 
                        _wallet.networkAvailable ? 'Yes ✅' : 'No ❌',
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Info about auto-publish
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your GNS record is published automatically when you claim a handle or update your profile.',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // ============================================================
              // 🐆 gSITE CREATOR
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

  Widget _buildInfoRow(String label, String value, {String? fullValue}) {
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
          child: GestureDetector(
            onTap: fullValue != null 
                ? () => _copyToClipboard(fullValue, label)
                : null,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: fullValue != null ? Colors.deepPurple : null,
                decoration: fullValue != null ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
        if (fullValue != null)
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _copyToClipboard(fullValue, label),
            color: Colors.grey,
          ),
      ],
    );
  }
}
