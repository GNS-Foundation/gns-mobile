// Identity Viewer Screen - Phase 3B.2 (FINAL - With Dependency Injection)
//
// Displays another user's GNS identity with full profile information.
//
// Location: lib/ui/screens/identity_viewer_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/profile/identity_view_data.dart';
import '../../core/profile/profile_module.dart';
import '../../core/contacts/contact_storage.dart';
import '../../core/contacts/contact_entry.dart';
import '../../core/comm/communication_service.dart';

class IdentityViewerScreen extends StatefulWidget {
  final IdentityViewData identity;
  final CommunicationService commService;  // ✅ Injected dependency

  const IdentityViewerScreen({
    super.key,
    required this.identity,
    required this.commService,  // ✅ Required parameter
  });

  @override
  State<IdentityViewerScreen> createState() => _IdentityViewerScreenState();
}

class _IdentityViewerScreenState extends State<IdentityViewerScreen> {
  final _contactStorage = ContactStorage();
  bool _isContact = false;
  bool _isLoading = false;

  // ✅ Access via widget (no initialization needed)
  CommunicationService get _commService => widget.commService;

  @override
  void initState() {
    super.initState();
    _isContact = widget.identity.isContact;
    // ✅ No service initialization needed - it's injected!
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.identity;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Text(
          identity.displayTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'copy_pk', child: Text('Copy Public Key')),
              const PopupMenuItem(value: 'copy_gns', child: Text('Copy GNS ID')),
              if (_isContact) ...[
                const PopupMenuItem(value: 'remove_contact', child: Text('Remove Contact')),
              ],
              const PopupMenuItem(value: 'report', child: Text('Report Identity')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Avatar & Handle
            _buildHeader(identity),
            const SizedBox(height: 24),

            // Profile Info Card
            if (identity.displayName != null || identity.bio != null || identity.links.isNotEmpty)
              _buildProfileCard(identity),
            if (identity.displayName != null || identity.bio != null || identity.links.isNotEmpty)
              const SizedBox(height: 16),

            // Stats Row
            _buildStatsRow(identity),
            const SizedBox(height: 16),

            // Verification Info
            _buildVerificationCard(identity),
            const SizedBox(height: 24),

            // Action Buttons
            if (!identity.isOwnIdentity) _buildActionButtons(identity),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(IdentityViewData identity) {
    return Column(
      children: [
        // Avatar
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: _getTrustColor(identity.trustScore).withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _getTrustColor(identity.trustScore),
              width: 3,
            ),
          ),
          child: Center(
            child: identity.avatarUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Image.network(
                      identity.avatarUrl!,
                      fit: BoxFit.cover,
                      width: 94,
                      height: 94,
                      errorBuilder: (_, __, ___) =>
                          const Text('🔑', style: TextStyle(fontSize: 48)),
                    ),
                  )
                : const Text('🔑', style: TextStyle(fontSize: 48)),
          ),
        ),
        const SizedBox(height: 16),

        // Handle or GNS ID
        Text(
          identity.displayTitle,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3B82F6),
          ),
        ),
        const SizedBox(height: 4),

        // GNS ID (if has handle)
        if (identity.handle != null)
          Text(
            identity.gnsId,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white38,
              fontFamily: 'monospace',
            ),
          ),

        // Trust Badge
        const SizedBox(height: 12),
        _buildTrustBadge(identity.trustScore),
      ],
    );
  }

  Widget _buildProfileCard(IdentityViewData identity) {
    return Card(
      color: const Color(0xFF161B22),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display Name
            if (identity.displayName != null) ...[
              Text(
                identity.displayName!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Bio
            if (identity.bio != null) ...[
              Text(
                identity.bio!,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Links
            if (identity.links.isNotEmpty) ...[
              for (final link in identity.links) _buildLinkRow(link),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLinkRow(ProfileLink link) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(link.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              link.url,
              style: const TextStyle(
                color: Color(0xFF3B82F6),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(IdentityViewData identity) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatItem(
          '🍞',
          identity.breadcrumbLabel,
          'Breadcrumbs',
        ),
        _buildStatItem(
          identity.trustLevel.emoji,
          identity.trustLabel,
          'Trust',
        ),
        _buildStatItem(
          '📅',
          identity.daysLabel,
          'Active',
        ),
      ],
    );
  }

  Widget _buildStatItem(String emoji, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3B82F6),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard(IdentityViewData identity) {
    return Card(
      color: const Color(0xFF161B22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  identity.chainValid ? Icons.verified : Icons.warning_amber,
                  color: identity.chainValid ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  identity.chainValid ? 'Chain Verified' : 'Unverified',
                  style: TextStyle(
                    color: identity.chainValid ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.calendar_today,
              'Member since ${_formatDate(identity.createdAt)}',
            ),
            if (identity.lastSeen != null)
              _buildInfoRow(
                Icons.access_time,
                'Last active ${_formatRelative(identity.lastSeen!)}',
              ),
            if (identity.lastLocationRegion != null)
              _buildInfoRow(
                Icons.location_on,
                'Last seen: ${identity.lastLocationRegion}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(IdentityViewData identity) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _startMessage(identity),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Message'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : () => _toggleContact(identity),
            icon: Icon(_isContact ? Icons.person_remove : Icons.person_add),
            label: Text(_isContact ? 'Remove' : 'Add Contact'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _isContact ? Colors.red : Colors.white,
              side: BorderSide(
                color: _isContact ? Colors.red : Colors.white38,
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrustBadge(double trustScore) {
    final level = _getTrustLevel(trustScore);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: level.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: level.color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(level.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            level.label,
            style: TextStyle(
              color: level.color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  _TrustLevelInfo _getTrustLevel(double trustScore) {
    if (trustScore >= 80) {
      return _TrustLevelInfo('Trusted', Colors.green, '✅');
    } else if (trustScore >= 50) {
      return _TrustLevelInfo('Established', const Color(0xFF3B82F6), '🔵');
    } else if (trustScore >= 20) {
      return _TrustLevelInfo('Building', Colors.orange, '🟡');
    } else {
      return _TrustLevelInfo('New', Colors.red, '⚠️');
    }
  }

  Color _getTrustColor(double trustScore) {
    if (trustScore >= 80) return Colors.green;
    if (trustScore >= 50) return const Color(0xFF3B82F6);
    if (trustScore >= 20) return Colors.orange;
    return Colors.red;
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _formatRelative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _formatDate(date);
  }

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'copy_pk':
        await Clipboard.setData(ClipboardData(text: widget.identity.publicKey));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Public key copied')),
          );
        }
        break;
      case 'copy_gns':
        await Clipboard.setData(ClipboardData(text: widget.identity.gnsId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('GNS ID copied')),
          );
        }
        break;
      case 'remove_contact':
        _toggleContact(widget.identity);
        break;
      case 'report':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report feature coming soon')),
        );
        break;
    }
  }

  Future<void> _toggleContact(IdentityViewData identity) async {
    setState(() => _isLoading = true);

    try {
      if (_isContact) {
        await _contactStorage.removeContact(identity.publicKey);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contact removed')),
          );
        }
      } else {
        // ✅ Fetch encryption key before adding contact (uses injected service)
        String? encryptionKey;
        
        if (identity.handle != null) {
          try {
            final handleInfo = await _commService.resolveHandleInfo(identity.handle!);
            encryptionKey = handleInfo?['encryption_key'] as String?;
            debugPrint('✅ Fetched encryption key for ${identity.handle}: ${encryptionKey?.substring(0, 16)}...');
          } catch (e) {
            debugPrint('⚠️ Failed to fetch encryption key: $e');
          }
        }
        
        final contact = ContactEntry(
          publicKey: identity.publicKey,
          encryptionKey: encryptionKey,  // ✅ Store X25519 encryption key
          handle: identity.handle,
          displayName: identity.displayName,
          avatarUrl: identity.avatarUrl,
          trustScore: identity.trustScore,
          addedAt: DateTime.now(),
        );
        await _contactStorage.addContact(contact);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${identity.displayLabel} added to contacts')),
          );
        }
      }

      setState(() => _isContact = !_isContact);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startMessage(IdentityViewData identity) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Messaging coming in Phase 3B.5')),
    );
  }
}

class _TrustLevelInfo {
  final String label;
  final Color color;
  final String emoji;

  _TrustLevelInfo(this.label, this.color, this.emoji);
}
