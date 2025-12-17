/// Search Screen - v2 (Live Search)
///
/// Improved search with:
/// - Live results as you type
/// - Works without @ symbol
/// - Searches local contacts + network
/// - Debounced API calls
///
/// Location: lib/ui/screens/search_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/profile/profile_service.dart';
import '../../core/profile/identity_view_data.dart';
import '../../core/contacts/contact_entry.dart';
import '../../core/theme/theme_service.dart';

class SearchScreen extends StatefulWidget {
  final ProfileService profileService;

  const SearchScreen({super.key, required this.profileService});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  // Search state
  bool _isSearching = false;
  String? _error;
  List<SearchResult> _results = [];
  List<ContactEntry> _localContacts = [];
  Timer? _debounceTimer;

  // Minimum characters to start searching
  static const int _minSearchLength = 1;
  
  // Debounce delay (ms)
  static const int _debounceDelay = 300;

  @override
  void initState() {
    super.initState();
    _loadLocalContacts();
    
    // Listen to search input changes
    _searchController.addListener(_onSearchChanged);
    
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Load local contacts for instant filtering
  Future<void> _loadLocalContacts() async {
    final contacts = await widget.profileService.getContacts();
    if (mounted) {
      setState(() => _localContacts = contacts);
    }
  }

  /// Called on every keystroke - debounced
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    
    // Cancel previous timer
    _debounceTimer?.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _isSearching = false;
      });
      return;
    }
    
    // Show local results immediately
    _filterLocalContacts(query);
    
    // Debounce network search
    if (query.length >= _minSearchLength) {
      setState(() => _isSearching = true);
      
      _debounceTimer = Timer(
        const Duration(milliseconds: _debounceDelay),
        () => _performNetworkSearch(query),
      );
    }
  }

  /// Filter local contacts (instant)
  void _filterLocalContacts(String query) {
    final normalizedQuery = _normalizeQuery(query);
    
    final localMatches = _localContacts.where((contact) {
      final handle = (contact.handle ?? '').toLowerCase();
      final displayName = (contact.displayName ?? '').toLowerCase();
      final publicKey = contact.publicKey.toLowerCase();
      
      return handle.contains(normalizedQuery) ||
             displayName.contains(normalizedQuery) ||
             publicKey.startsWith(normalizedQuery);
    }).map((c) => SearchResult(
      type: SearchResultType.contact,
      handle: c.handle,
      displayName: c.displayName,
      publicKey: c.publicKey,
      avatarUrl: c.avatarUrl,
      isLocal: true,
    )).toList();
    
    setState(() {
      // Keep local matches at top, then network results
      final networkResults = _results.where((r) => !r.isLocal).toList();
      _results = [...localMatches, ...networkResults];
    });
  }

  /// Search network API (debounced)
  Future<void> _performNetworkSearch(String query) async {
    final normalizedQuery = _normalizeQuery(query);
    
    if (normalizedQuery.length < _minSearchLength) {
      setState(() => _isSearching = false);
      return;
    }
    
    try {
      // Call the search API
      final networkResults = await widget.profileService.searchIdentities(normalizedQuery);
      
      if (!mounted) return;
      
      // Merge with local results (local first, avoid duplicates)
      final localPks = _results
          .where((r) => r.isLocal)
          .map((r) => r.publicKey.toLowerCase())
          .toSet();
      
      final uniqueNetworkResults = networkResults
          .where((r) => !localPks.contains(r.publicKey.toLowerCase()))
          .toList();
      
      setState(() {
        final localResults = _results.where((r) => r.isLocal).toList();
        _results = [...localResults, ...uniqueNetworkResults];
        _isSearching = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          // Only show error if no local results
          if (_results.isEmpty) {
            _error = 'Search failed: $e';
          }
        });
      }
    }
  }

  /// Normalize query (remove @, lowercase)
  String _normalizeQuery(String query) {
    return query.replaceAll('@', '').toLowerCase().trim();
  }

  /// Select a search result
  void _selectResult(SearchResult result) async {
    // Save to search history
    await widget.profileService.addToSearchHistory(result.handle ?? result.publicKey);
    
    // Look up full identity
    final fullResult = await widget.profileService.lookupByPublicKey(result.publicKey);
    
    if (fullResult.success && fullResult.identity != null && mounted) {
      Navigator.pop(context, fullResult.identity);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fullResult.error ?? 'Could not load identity')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final showResults = query.isNotEmpty;
    
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(context),
        title: const Text('Search'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.surface(context),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: AppTheme.textPrimary(context)),
              decoration: InputDecoration(
                hintText: 'Search by name or @handle...',
                hintStyle: TextStyle(color: AppTheme.textMuted(context)),
                prefixIcon: Icon(Icons.search, color: AppTheme.textMuted(context)),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: AppTheme.textMuted(context)),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.background(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          // Results or Empty State
          Expanded(
            child: showResults ? _buildResults() : _buildEmptyState(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty && !_isSearching) {
      // No results found
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: AppTheme.textMuted(context),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(
                color: AppTheme.textMuted(context),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _SearchResultTile(
          result: result,
          query: _normalizeQuery(_searchController.text),
          onTap: () => _selectResult(result),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          
          // QR Scanner Button
          _ActionCard(
            icon: Icons.qr_code_scanner,
            title: 'Scan QR Code',
            subtitle: 'Scan someone\'s identity QR',
            onTap: _openQrScanner,
          ),
          
          const SizedBox(height: 16),
          
          // Tips
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tips_and_updates, 
                         size: 20, 
                         color: AppTheme.textSecondary(context)),
                    const SizedBox(width: 8),
                    Text(
                      'Search Tips',
                      style: TextStyle(
                        color: AppTheme.textPrimary(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _TipRow(icon: Icons.alternate_email, text: 'Type handle without @'),
                _TipRow(icon: Icons.person, text: 'Search by display name'),
                _TipRow(icon: Icons.key, text: 'Paste a public key'),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Recent searches could go here
        ],
      ),
    );
  }

  void _openQrScanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR Scanner coming soon!')),
    );
  }
}

// ===========================================
// SEARCH RESULT MODEL
// ===========================================

enum SearchResultType { contact, network }

class SearchResult {
  final SearchResultType type;
  final String? handle;
  final String? displayName;
  final String publicKey;
  final String? avatarUrl;
  final bool isLocal;
  final double? trustScore;

  SearchResult({
    required this.type,
    this.handle,
    this.displayName,
    required this.publicKey,
    this.avatarUrl,
    this.isLocal = false,
    this.trustScore,
  });
}

// ===========================================
// SEARCH RESULT TILE
// ===========================================

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final String query;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.result,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final handle = result.handle;
    final displayName = result.displayName ?? handle ?? 'Unknown';
    final shortPk = '${result.publicKey.substring(0, 8)}...';

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: _getAvatarColor(result.publicKey),
        backgroundImage: result.avatarUrl != null 
            ? NetworkImage(result.avatarUrl!) 
            : null,
        child: result.avatarUrl == null
            ? Text(
                (handle ?? displayName).substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: _buildHighlightedText(displayName, query, context),
      subtitle: Row(
        children: [
          if (handle != null) ...[
            Text(
              '@$handle',
              style: TextStyle(
                color: AppTheme.textSecondary(context),
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            shortPk,
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result.isLocal)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'CONTACT',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right,
            color: AppTheme.textMuted(context),
          ),
        ],
      ),
    );
  }

  /// Highlight matching text
  Widget _buildHighlightedText(String text, String query, BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: TextStyle(color: AppTheme.textPrimary(context)));
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerQuery);

    if (matchIndex == -1) {
      return Text(text, style: TextStyle(color: AppTheme.textPrimary(context)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 16),
        children: [
          TextSpan(text: text.substring(0, matchIndex)),
          TextSpan(
            text: text.substring(matchIndex, matchIndex + query.length),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          TextSpan(text: text.substring(matchIndex + query.length)),
        ],
      ),
    );
  }

  Color _getAvatarColor(String pk) {
    final hash = pk.hashCode;
    final colors = [
      Colors.blue,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
    ];
    return colors[hash.abs() % colors.length];
  }
}

// ===========================================
// HELPER WIDGETS
// ===========================================

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.blue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.textPrimary(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppTheme.textMuted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textMuted(context)),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
