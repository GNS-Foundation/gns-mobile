// Identity Viewer Screen - FIXED with working MESSAGE button
//
// Displays another user's GNS identity with full profile information.
// MESSAGE button now opens ConversationScreen instead of showing placeholder.
//
// ✅ Takes profileService (matches existing calls in home_tab.dart and contacts_tab.dart)
// ✅ Optionally takes wallet (for backwards compatibility)
// ✅ Creates CommunicationService internally for messaging
//
// Location: lib/ui/screens/identity_viewer_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/profile/identity_view_data.dart';
import '../../core/profile/profile_service.dart';
import '../../core/contacts/contact_storage.dart';
import '../../core/contacts/contact_entry.dart';
import '../../core/comm/communication_service.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import '../messages/conversation_screen.dart';

class IdentityViewerScreen extends StatefulWidget {
  final IdentityViewData identity;
  final ProfileService profileService;
  final IdentityWallet? wallet;  // Optional for backwards compatibility

  const IdentityViewerScreen({
    super.key,
    required this.identity,
    required this.profileService,
    this.wallet,  // Optional
  });

  @override
  State<IdentityViewerScreen> createState() => _IdentityViewerScreenState();
}

class _IdentityViewerScreenState extends State<IdentityViewerScreen> {
  final _contactStorage = ContactStorage();
  late IdentityWallet _wallet;
  CommunicationService? _commService;
  
  bool _isContact = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isContact = widget.identity.isContact;
    _wallet = widget.wallet ?? IdentityWallet();
    _initializeCommService();
  }

  Future<void> _initializeCommService() async {
    try {
      if (!_wallet.isInitialized) {
        await _wallet.initialize();
      }
      _commService = CommunicationService.instance(_wallet);
      await _commService!.initialize();
    } catch (e) {
      debugPrint('⚠️ Failed to initialize comm service: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.identity;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header with Avatar
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
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      identity.displayName!,
                      style: TextStyle(
                        fontSize: 18,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                if (identity.bio != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      identity.bio!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary(context)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatBox(identity.breadcrumbLabel, 'Crumbs', '🍞'),
              _buildStatBox(identity.trustLabel, 'Trust', identity.trustLevel.emoji),
              _buildStatBox(identity.daysLabel, 'Active', '📅'),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Send GNS Tokens Card
          Card(
            color: AppTheme.surface(context).withOpacity(0.5),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('G', style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold, fontSize: 18))),
              ),
              title: const Text('Send GNS Tokens', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Send tokens to ${identity.displayTitle}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Token sending coming soon!')),
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Links
          if (identity.links.isNotEmpty) ...[
            const Text(
              'LINKS',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            ...identity.links.map((link) => ListTile(
              leading: Text(link.icon, style: const TextStyle(fontSize: 20)),
              title: Text(link.url),
              onTap: () {
                // TODO: Open URL
              },
            )),
            const SizedBox(height: 16),
          ],
          
          // Action Buttons
          if (!identity.isOwnIdentity) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(_isContact ? Icons.check : Icons.person_add),
                    label: Text(_isContact ? 'CONTACT' : 'ADD CONTACT'),
                    onPressed: _isLoading ? null : (_isContact ? null : () => _toggleContact(identity)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: _isContact ? AppTheme.textMuted(context) : AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.message),
                    label: const Text('MESSAGE'),
                    onPressed: _isLoading ? null : () => _startMessage(identity),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatBox(String value, String label, String icon) {
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
        // Fetch encryption key if we have a handle
        String? encryptionKey;
        if (identity.handle != null && _commService != null) {
          try {
            final handleInfo = await _commService!.resolveHandleInfo(identity.handle!);
            encryptionKey = handleInfo?['encryption_key'] as String?;
          } catch (e) {
            debugPrint('⚠️ Failed to fetch encryption key: $e');
          }
        }
        
        final contact = ContactEntry(
          publicKey: identity.publicKey,
          encryptionKey: encryptionKey,
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

      if (mounted) {
        setState(() => _isContact = !_isContact);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// ✅ FIXED: Start a message conversation with this user
  Future<void> _startMessage(IdentityViewData identity) async {
    // Ensure comm service is ready
    if (_commService == null) {
      await _initializeCommService();
    }
    
    if (_commService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to initialize messaging')),
        );
      }
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      // First, ensure contact is added with encryption key
      final existingContact = await _contactStorage.getContact(identity.publicKey);
      
      if (existingContact == null) {
        // Fetch encryption key if we have a handle
        String? encryptionKey;
        if (identity.handle != null) {
          try {
            final handleInfo = await _commService!.resolveHandleInfo(identity.handle!);
            encryptionKey = handleInfo?['encryption_key'] as String?;
          } catch (e) {
            debugPrint('⚠️ Failed to fetch encryption key: $e');
          }
        }
        
        // Add contact with encryption key
        await _contactStorage.addContact(ContactEntry(
          publicKey: identity.publicKey,
          encryptionKey: encryptionKey,
          handle: identity.handle,
          displayName: identity.displayName,
          avatarUrl: identity.avatarUrl,
          trustScore: identity.trustScore,
          addedAt: DateTime.now(),
        ));
        
        if (mounted) {
          setState(() => _isContact = true);
        }
      }
      
      // Check if we already have a thread with this user
      final existingThread = await _commService!.findThreadByParticipant(identity.publicKey);
      
      if (existingThread != null) {
        // Open existing conversation
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ConversationScreen(
                thread: existingThread,
                commService: _commService!,
              ),
            ),
          );
        }
      } else {
        // Create a new thread
        final thread = await _commService!.createThread(
          participantKeys: [identity.publicKey],
          title: identity.handle != null ? '@${identity.handle}' : null,
        );
        
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ConversationScreen(
                thread: thread,
                commService: _commService!,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting conversation: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
