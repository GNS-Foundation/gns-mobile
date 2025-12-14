/// Identity Viewer Screen
/// 
/// View another user's identity details with Send GNS functionality.
/// 
/// Location: lib/ui/profile/identity_viewer_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/profile/profile_service.dart';
import '../../core/profile/identity_view_data.dart';
import '../../core/theme/theme_service.dart';
import '../widgets/send_gns_sheet.dart';

// ==================== IDENTITY VIEWER SCREEN ====================

class IdentityViewerScreen extends StatelessWidget {
  final IdentityViewData identity;
  final ProfileService profileService;
  final IdentityWallet? wallet; // Optional - needed for sending GNS

  const IdentityViewerScreen({
    super.key,
    required this.identity,
    required this.profileService,
    this.wallet,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: identity.avatarUrl != null
                      ? ClipOval(
                          child: Image.network(
                            identity.avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Center(child: Text('👤', style: TextStyle(fontSize: 36))),
                          ),
                        )
                      : const Center(child: Text('👤', style: TextStyle(fontSize: 36))),
                ),
                const SizedBox(height: 16),
                Text(
                  identity.displayTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
                if (identity.displayName != null)
                  Text(
                    identity.displayName!,
                    style: const TextStyle(fontSize: 18),
                  ),
                if (identity.bio != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    identity.bio!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatBox(value: identity.breadcrumbLabel, label: 'Crumbs', icon: '🍞'),
              _StatBox(value: identity.trustLabel, label: 'Trust', icon: identity.trustLevel.emoji),
              _StatBox(value: identity.daysLabel, label: 'Active', icon: '📅'),
            ],
          ),
          const SizedBox(height: 24),
          if (identity.links.isNotEmpty) ...[
            const Text(
              'LINKS',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            ...identity.links.map((link) => ListTile(
              leading: Text(link.icon, style: const TextStyle(fontSize: 20)),
              title: Text(link.url),
              onTap: () {},
            )),
            const SizedBox(height: 16),
          ],
          if (!identity.isOwnIdentity) ...[
            // Send GNS Button (NEW!)
            _buildSendGnsButton(context),
            const SizedBox(height: 12),
            
            // Contact & Message buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(identity.isContact ? Icons.check : Icons.person_add),
                    label: Text(identity.isContact ? 'CONTACT' : 'ADD CONTACT'),
                    onPressed: identity.isContact
                        ? null
                        : () async {
                            await profileService.addContact(identity);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to contacts')),
                            );
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.message),
                    label: const Text('MESSAGE'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Messaging coming in Phase 5!')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSendGnsButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4CAF50).withOpacity(0.15),
            const Color(0xFF2196F3).withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showSendGnsSheet(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text('G', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Send GNS Tokens',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Send tokens to ${identity.handle != null ? "@${identity.handle}" : "this user"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF4CAF50)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSendGnsSheet(BuildContext context) {
    if (wallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallet not available')),
      );
      return;
    }
    
    SendGnsSheet.show(
      context: context,
      wallet: wallet!,
      recipientPublicKey: identity.publicKey,
      recipientHandle: identity.handle,
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final String icon;

  const _StatBox({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context)),
            ),
          ],
        ),
      ),
    );
  }
}
