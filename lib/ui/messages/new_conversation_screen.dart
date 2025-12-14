/// New Conversation Screen - Start New Chat (FIXED with encryption key storage)
/// 
/// Search for users by @handle or public key to start conversations.
/// 
/// Location: lib/ui/messages/new_conversation_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/comm/communication_service.dart';
import '../../core/comm/message_storage.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/theme/theme_service.dart';
import '../../core/contacts/contact_storage.dart';  // ✅ ADDED
import '../../core/contacts/contact_entry.dart';    // ✅ ADDED
import 'conversation_screen.dart';

class NewConversationScreen extends StatefulWidget {
  final CommunicationService commService;
  final IdentityWallet wallet;

  const NewConversationScreen({
    super.key,
    required this.commService,
    required this.wallet,
  });

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  List<RecentContact> _recentContacts = [];
  List<SearchResult> _searchResults = [];
  bool _searching = false;
  bool _loading = true;
  String? _error;
  
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadRecentContacts();
    _searchController.addListener(_onSearchChanged);
    
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentContacts() async {
    try {
      final threads = await widget.commService.getThreads();
      final myKey = widget.wallet.publicKey?.toLowerCase();
      
      final contacts = <RecentContact>[];
      for (final threadPreview in threads) {
        final thread = threadPreview.thread;
        final otherKey = thread.participantKeys.firstWhere(
          (k) => k.toLowerCase() != myKey,
          orElse: () => thread.participantKeys.first,
        );
        
        contacts.add(RecentContact(
          publicKey: otherKey,
          handle: thread.title,
          lastMessageAt: thread.updatedAt,
          threadId: thread.id,
        ));
      }
      
      setState(() {
        _recentContacts = contacts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    
    setState(() => _searching = true);
    
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final results = <SearchResult>[];
      
      // Check if it's a valid public key (64 hex chars)
      final cleanQuery = query.toLowerCase().replaceAll('@', '');
      
      if (RegExp(r'^[a-f0-9]{64}$').hasMatch(cleanQuery)) {
        // It's a public key
        results.add(SearchResult(
          publicKey: cleanQuery,
          type: SearchResultType.publicKey,
        ));
      }
      
      // Check if it looks like a handle
      if (RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(cleanQuery)) {
        // Try to resolve the handle via GNS
        try {
          final handleInfo = await widget.commService.resolveHandleInfo(cleanQuery);
          if (handleInfo != null) {
            results.add(SearchResult(
              publicKey: handleInfo['public_key'] as String?,
              handle: cleanQuery,
              encryptionKey: handleInfo['encryption_key'] as String?,  // ✅ ADDED - Store encryption key in result
              type: handleInfo['is_system'] == true 
                  ? SearchResultType.systemBot 
                  : SearchResultType.handle,
              botType: handleInfo['type'] as String?,
            ));
          } else {
            // Handle not found, but show as suggestion
            results.add(SearchResult(
              handle: cleanQuery,
              type: SearchResultType.handleNotFound,
            ));
          }
        } catch (_) {
          // Handle resolution failed - try legacy resolve
          final resolved = await widget.commService.resolveHandle(cleanQuery);
          if (resolved != null) {
            results.add(SearchResult(
              publicKey: resolved,
              handle: cleanQuery,
              type: SearchResultType.handle,
            ));
          }
        }
      }
      
      // Search recent contacts
      for (final contact in _recentContacts) {
        final matchesKey = contact.publicKey.toLowerCase().contains(cleanQuery);
        final matchesHandle = contact.handle?.toLowerCase().contains(cleanQuery) ?? false;
        
        if (matchesKey || matchesHandle) {
          results.add(SearchResult(
            publicKey: contact.publicKey,
            handle: contact.handle,
            type: SearchResultType.recentContact,
          ));
        }
      }
      
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (e) {
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        title: const Text(
          'NEW MESSAGE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search field
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              border: Border(bottom: BorderSide(color: AppTheme.border(context))),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              style: TextStyle(color: AppTheme.textPrimary(context)),
              decoration: InputDecoration(
                hintText: 'Search @handle or paste public key...',
                hintStyle: TextStyle(color: AppTheme.textMuted(context)),
                prefixIcon: Icon(Icons.search, color: AppTheme.textMuted(context)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: AppTheme.textMuted(context)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                          });
                        },
                      )
                    : IconButton(
                        icon: Icon(Icons.qr_code_scanner, color: AppTheme.textMuted(context)),
                        onPressed: _scanQrCode,
                      ),
                filled: true,
                fillColor: AppTheme.surfaceLight(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          
          // Content
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
      );
    }

    // Show search results if searching
    if (_searchController.text.isNotEmpty) {
      if (_searching) {
        return Center(
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        );
      }
      
      if (_searchResults.isEmpty) {
        return _buildNoResults();
      }
      
      return _buildSearchResults();
    }

    // Show recent contacts
    return _buildRecentContacts();
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: AppTheme.textMuted(context).withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching by @handle\nor pasting a public key',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: AppTheme.border(context),
        indent: 72,
      ),
      itemBuilder: (context, index) {
        return _buildSearchResultTile(_searchResults[index]);
      },
    );
  }

  Widget _buildSearchResultTile(SearchResult result) {
    IconData icon;
    Color iconColor;
    String title;
    String? subtitle;
    bool enabled = true;

    switch (result.type) {
      case SearchResultType.systemBot:
        icon = Icons.smart_toy;
        iconColor = AppTheme.accent;
        title = result.handle != null ? '@${result.handle}' : result.publicKey!.substring(0, 12);
        subtitle = result.botType == 'echo' 
            ? '🤖 Echo Bot - Test your messages!'
            : 'System Bot';
        break;
      case SearchResultType.handle:
        icon = Icons.alternate_email;
        iconColor = Theme.of(context).colorScheme.primary;
        title = '@${result.handle}';
        subtitle = result.publicKey?.substring(0, 16);
        break;
      case SearchResultType.handleNotFound:
        icon = Icons.search_off;
        iconColor = Colors.red;
        title = '@${result.handle} not found';
        subtitle = 'This handle is not registered';
        enabled = false;
        break;
      case SearchResultType.publicKey:
        icon = Icons.key;
        iconColor = Theme.of(context).colorScheme.secondary;
        title = '${result.publicKey!.substring(0, 16)}...';
        subtitle = 'Public key';
        break;
      case SearchResultType.recentContact:
        icon = Icons.chat_bubble_outline;
        iconColor = AppTheme.textSecondary(context);
        title = result.handle ?? '${result.publicKey!.substring(0, 12)}...';
        subtitle = 'Recent contact';
        break;
      default:
        icon = Icons.person;
        iconColor = AppTheme.textSecondary(context);
        title = result.handle ?? result.publicKey ?? 'Unknown';
        subtitle = null;
        break;
    }

    return ListTile(
      enabled: enabled,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: enabled 
              ? AppTheme.textPrimary(context)
              : AppTheme.textMuted(context),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color: enabled 
                    ? AppTheme.textSecondary(context)
                    : AppTheme.textMuted(context).withOpacity(0.5),
                fontSize: 12,
              ),
            )
          : null,
      trailing: enabled
          ? Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textMuted(context))
          : null,
      onTap: enabled ? () => _startConversation(result) : null,
    );
  }

  Widget _buildRecentContacts() {
    if (_recentContacts.isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'RECENT',
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        ..._recentContacts.map((contact) => _buildContactTile(contact)),
      ],
    );
  }

  Widget _buildContactTile(RecentContact contact) {
    final displayName = contact.handle ?? '${contact.publicKey.substring(0, 12)}...';
    final initial = displayName.replaceAll('@', '').substring(0, 1).toUpperCase();

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        child: Text(
          initial,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        displayName.startsWith('@') ? displayName : '@$displayName',
        style: TextStyle(
          color: AppTheme.textPrimary(context),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        _formatTime(contact.lastMessageAt),
        style: TextStyle(color: AppTheme.textMuted(context), fontSize: 12),
      ),
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textMuted(context)),
      onTap: () => _openExistingThread(contact),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search, size: 64, color: AppTheme.textMuted(context).withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            'Start a conversation',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Search for someone by their @handle\nor paste their public key',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted(context)),
          ),
          const SizedBox(height: 24),
          // Suggest @echo
          ElevatedButton.icon(
            onPressed: () {
              _searchController.text = 'echo';
            },
            icon: const Icon(Icons.smart_toy),
            label: const Text('Message @echo bot'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pasteFromClipboard,
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste from clipboard'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  // ⭐⭐⭐ CRITICAL FIX - Add contact with encryption key BEFORE starting conversation ⭐⭐⭐
  Future<void> _startConversation(SearchResult result) async {
    if (result.publicKey == null) return;

    // ✅ NEW: Add to contacts database with encryption key FIRST!
    try {
      final contactStorage = ContactStorage();
      
      // Check if contact already exists
      final existingContact = await contactStorage.getContact(result.publicKey!);
      
      if (existingContact == null) {
        // ✅ Fetch encryption key if we have a handle but no encryption key in result
        String? encryptionKey = result.encryptionKey;
        
        if (encryptionKey == null && result.handle != null) {
          try {
            final handleInfo = await widget.commService.resolveHandleInfo(result.handle!);
            encryptionKey = handleInfo?['encryption_key'] as String?;
            debugPrint('✅ Fetched encryption key for @${result.handle}: ${encryptionKey?.substring(0, 16)}...');
          } catch (e) {
            debugPrint('⚠️ Failed to fetch encryption key for @${result.handle}: $e');
          }
        }
        
        // ✅ Add contact with encryption key
        await contactStorage.addContact(ContactEntry(
          publicKey: result.publicKey!,
          encryptionKey: encryptionKey,  // ⭐ CRITICAL - Store X25519 encryption key
          handle: result.handle,
          displayName: result.handle != null ? '@${result.handle}' : null,
          avatarUrl: null,
          trustScore: result.type == SearchResultType.systemBot ? 100.0 : 0.0,
          addedAt: DateTime.now(),
        ));
        
        debugPrint('✅ Added @${result.handle ?? result.publicKey!.substring(0, 8)} to contacts with encryption key');
      }
    } catch (e) {
      debugPrint('⚠️ Error adding contact: $e');
      // Continue anyway - conversation might still work without stored contact
    }

    // Check if we already have a thread with this user
    final existingThread = await widget.commService.findThreadByParticipant(result.publicKey!);
    
    if (existingThread != null) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ConversationScreen(
              thread: existingThread,
              commService: widget.commService,
            ),
          ),
        );
      }
      return;
    }

    // Create a new thread
    final thread = await widget.commService.createThread(
      participantKeys: [result.publicKey!],
      title: result.handle != null ? '@${result.handle}' : null,
    );

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ConversationScreen(
            thread: thread,
            commService: widget.commService,
          ),
        ),
      );
    }
  }

  void _openExistingThread(RecentContact contact) async {
    if (contact.threadId != null) {
      final thread = await widget.commService.getThread(contact.threadId!);
      if (thread != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ConversationScreen(
              thread: thread,
              commService: widget.commService,
            ),
          ),
        );
      }
    } else {
      _startConversation(SearchResult(
        publicKey: contact.publicKey,
        handle: contact.handle,
        type: SearchResultType.recentContact,
      ));
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _searchController.text = data!.text!;
    }
  }

  void _scanQrCode() {
    // TODO: Implement QR code scanning
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR scanning coming soon!')),
    );
  }
}

class RecentContact {
  final String publicKey;
  final String? handle;
  final DateTime lastMessageAt;
  final String? threadId;

  RecentContact({
    required this.publicKey,
    this.handle,
    required this.lastMessageAt,
    this.threadId,
  });
}

class SearchResult {
  final String? publicKey;
  final String? handle;
  final String? encryptionKey;  // ✅ ADDED
  final SearchResultType type;
  final String? botType;

  SearchResult({
    this.publicKey,
    this.handle,
    this.encryptionKey,  // ✅ ADDED
    required this.type,
    this.botType,
  });
}

enum SearchResultType {
  handle,
  handleNotFound,
  publicKey,
  recentContact,
  systemBot,  // NEW: For @echo, @support, etc.
}
