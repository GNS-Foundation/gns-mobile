// Search Screen - Phase 3B.1
//
// Search for GNS identities by @handle or public key.
//
// Location: lib/ui/screens/search_screen.dart

import 'package:flutter/material.dart';
import '../../core/profile/profile_service.dart';
import '../../core/profile/identity_view_data.dart';
import '../../core/contacts/contact_entry.dart';

class SearchScreen extends StatefulWidget {
  final ProfileService profileService;
  
  const SearchScreen({super.key, required this.profileService});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  bool _isSearching = false;
  String? _error;
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    // Load from profile service search history
    final history = await widget.profileService.getRecentSearches();
    setState(() {
      _recentSearches = history.map((h) => h.query).toList();
    });
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
    });

    final result = await widget.profileService.search(query);

    if (!mounted) return;

    if (result.success && result.identity != null) {
      // Navigate to identity viewer
      Navigator.pop(context, result.identity);
    } else {
      setState(() {
        _error = result.error ?? 'Identity not found';
      });
    }

    setState(() => _isSearching = false);
  }

  void _clearRecentSearches() async {
    await widget.profileService.clearSearchHistory();
    setState(() => _recentSearches = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Search Identities'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF161B22),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  onSubmitted: (_) => _performSearch(),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '@handle or public key...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white38),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _error = null);
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                    ),
                  ),
                  onChanged: (value) => setState(() {}),
                ),
                const SizedBox(height: 12),
                
                // Search Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSearching ? null : _performSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSearching
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'SEARCH',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // Error Message
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),

          // QR Scanner Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openQrScanner,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR Code'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF30363D)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Recent Searches
          if (_recentSearches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'RECENT SEARCHES',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  TextButton(
                    onPressed: _clearRecentSearches,
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: Color(0xFF3B82F6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _recentSearches.length,
                itemBuilder: (context, index) {
                  final search = _recentSearches[index];
                  return ListTile(
                    leading: const Icon(Icons.history, color: Colors.white38),
                    title: Text(
                      search,
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.north_west, color: Colors.white38, size: 16),
                    onTap: () {
                      _searchController.text = search;
                      _performSearch();
                    },
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
          ] else ...[
            // Empty state
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search,
                      size: 64,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Search for identities',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter @handle or public key',
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Help Text
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Search Examples',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• @username - Search by handle\n'
                    '• 26b9c6a8... - Search by public key\n'
                    '• gns_26b9c6a8 - Search by GNS ID',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openQrScanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR Scanner coming in Phase 3B.3')),
    );
  }
}
