/// Identity Details Screen
///
/// Shows the user's public cryptographic identity — safe to view and share.
/// All values shown here are PUBLIC keys. Private keys never leave the Keychain.
///
/// Location: lib/ui/screens/identity_details_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';

class IdentityDetailsScreen extends StatelessWidget {
  const IdentityDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = IdentityWallet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Explainer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_open_outlined, color: AppTheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'These are your PUBLIC keys — safe to share. '
                    'Your private keys never leave the device Keychain and are never shown here.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Keys card
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border(context)),
            ),
            child: Column(
              children: [
                _KeyRow(
                  label: 'GNS ID',
                  value: wallet.gnsId ?? '—',
                  icon: Icons.fingerprint,
                  context: context,
                ),
                Divider(height: 1, color: AppTheme.border(context)),
                _KeyRow(
                  label: 'Ed25519 Public Key',
                  value: wallet.publicKey ?? '—',
                  icon: Icons.vpn_key_outlined,
                  context: context,
                ),
                Divider(height: 1, color: AppTheme.border(context)),
                _KeyRow(
                  label: 'X25519 Encryption Key',
                  value: wallet.encryptionPublicKeyHex ?? '—',
                  icon: Icons.enhanced_encryption_outlined,
                  context: context,
                ),
                Divider(height: 1, color: AppTheme.border(context)),
                _KeyRow(
                  label: 'Network',
                  value: wallet.networkAvailable ? 'Connected ✓' : 'Offline',
                  icon: Icons.cloud_outlined,
                  context: context,
                  copyable: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Auto-publish note
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    color: AppTheme.textSecondary(context), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your GNS record is published automatically when you claim a handle or update your profile.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final BuildContext context;
  final bool copyable;

  const _KeyRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.context,
    this.copyable = true,
  });

  void _copy() {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext bc) {
    final shortened = value.length > 20
        ? '${value.substring(0, 10)}…${value.substring(value.length - 6)}'
        : value;

    return ListTile(
      leading: Icon(icon, color: AppTheme.primary, size: 20),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.textSecondary(bc),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        shortened,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: copyable
          ? IconButton(
              icon: const Icon(Icons.copy, size: 18),
              color: AppTheme.textSecondary(bc),
              onPressed: _copy,
            )
          : null,
      onTap: copyable ? _copy : null,
    );
  }
}
