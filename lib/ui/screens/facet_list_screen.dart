/// Facet List Screen - Phase 4c (v2)
/// 
/// Displays all profile facets with template selection.
/// Templates now properly auto-fill the Facet ID.
/// 
/// Location: lib/ui/screens/facet_list_screen.dart

import 'package:flutter/material.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/profile/facet_storage.dart';
import 'facet_editor_screen.dart';
import 'dart:convert';
import 'dart:typed_data';

class FacetListScreen extends StatefulWidget {
  const FacetListScreen({super.key});

  @override
  State<FacetListScreen> createState() => _FacetListScreenState();
}

class _FacetListScreenState extends State<FacetListScreen> {
  final _storage = FacetStorage();
  List<ProfileFacet> _facets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFacets();
  }

  Future<void> _loadFacets() async {
    setState(() => _loading = true);
    try {
      await _storage.initialize();
      final facets = await _storage.getAllFacets();
      if (mounted) {
        setState(() {
          _facets = facets;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading facets: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Facets'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _facets.isEmpty
              ? _buildEmptyState()
              : _buildFacetList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddFacetSheet,
        icon: const Icon(Icons.add),
        label: const Text('ADD FACET'),
        backgroundColor: const Color(0xFF3B82F6),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎭', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'No Facets Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create different profiles for different audiences.\nSame identity, different faces.',
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFF8B949E)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddFacetSheet,
              icon: const Icon(Icons.add),
              label: const Text('CREATE YOUR FIRST FACET'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFacetList() {
    return RefreshIndicator(
      onRefresh: _loadFacets,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Explanation Card
          Card(
            color: const Color(0xFF1E3A5F).withOpacity(0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('🎭', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'One Identity, Many Faces',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Same @handle, same trust, different presentation.',
                          style: TextStyle(color: const Color(0xFF8B949E), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Facet List
          ..._facets.map((facet) => _buildFacetCard(facet)),
        ],
      ),
    );
  }

  Widget _buildFacetCard(ProfileFacet facet) {
    final avatarImage = facet.avatarUrl != null ? _decodeAvatar(facet.avatarUrl!) : null;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _editFacet(facet),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar/Emoji
              CircleAvatar(
                radius: 28,
                backgroundColor: _getFacetColor(facet.id).withOpacity(0.2),
                backgroundImage: avatarImage != null ? MemoryImage(avatarImage) : null,
                child: avatarImage == null
                    ? Text(facet.emoji, style: const TextStyle(fontSize: 24))
                    : null,
              ),
              const SizedBox(width: 16),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          facet.label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (facet.isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'DEFAULT',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (facet.displayName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        facet.displayName!,
                        style: TextStyle(color: const Color(0xFF8B949E)),
                      ),
                    ],
                    if (facet.bio != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        facet.bio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: const Color(0xFF6E7681), fontSize: 12),
                      ),
                    ],
                    // Show link icons
                    if (facet.links.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: facet.links.take(4).map((link) => 
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(link.icon, style: const TextStyle(fontSize: 14)),
                          ),
                        ).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              
              const Icon(Icons.chevron_right, color: Color(0xFF6E7681)),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddFacetSheet() {
    // Get list of already-used template IDs
    final usedIds = _facets.map((f) => f.id).toSet();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF30363D),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              const Text(
                'Create New Facet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a template or start from scratch',
                style: TextStyle(color: const Color(0xFF8B949E)),
              ),
              const SizedBox(height: 20),
              
              // Templates
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (!usedIds.contains('work'))
                    _TemplateChip(
                      emoji: '💼',
                      label: 'Work',
                      color: const Color(0xFF3B82F6),
                      onTap: () => _createFromTemplate('work'),
                    ),
                  if (!usedIds.contains('friends'))
                    _TemplateChip(
                      emoji: '🎉',
                      label: 'Friends',
                      color: const Color(0xFFF97316),
                      onTap: () => _createFromTemplate('friends'),
                    ),
                  if (!usedIds.contains('family'))
                    _TemplateChip(
                      emoji: '👨‍👩‍👧',
                      label: 'Family',
                      color: const Color(0xFFEC4899),
                      onTap: () => _createFromTemplate('family'),
                    ),
                  if (!usedIds.contains('travel'))
                    _TemplateChip(
                      emoji: '✈️',
                      label: 'Travel',
                      color: const Color(0xFF10B981),
                      onTap: () => _createFromTemplate('travel'),
                    ),
                  if (!usedIds.contains('creative'))
                    _TemplateChip(
                      emoji: '🎨',
                      label: 'Creative',
                      color: const Color(0xFF8B5CF6),
                      onTap: () => _createFromTemplate('creative'),
                    ),
                  if (!usedIds.contains('gaming'))
                    _TemplateChip(
                      emoji: '🎮',
                      label: 'Gaming',
                      color: const Color(0xFFEF4444),
                      onTap: () => _createFromTemplate('gaming'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Custom Option
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _createCustomFacet();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('CREATE CUSTOM FACET'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _createFromTemplate(String templateId) async {
    Navigator.pop(context); // Close bottom sheet
    
    ProfileFacet templateFacet;
    switch (templateId) {
      case 'work':
        templateFacet = ProfileFacet.workTemplate();
        break;
      case 'friends':
        templateFacet = ProfileFacet.friendsTemplate();
        break;
      case 'family':
        templateFacet = ProfileFacet.familyTemplate();
        break;
      case 'travel':
        templateFacet = ProfileFacet.travelTemplate();
        break;
      case 'creative':
        templateFacet = ProfileFacet.creativeTemplate();
        break;
      case 'gaming':
        templateFacet = ProfileFacet.gamingTemplate();
        break;
      default:
        templateFacet = ProfileFacet.defaultFacet();
    }
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacetEditorScreen(
          existingFacet: templateFacet,
          isNewFromTemplate: true,
        ),
      ),
    );
    
    _loadFacets();
  }

  void _createCustomFacet() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FacetEditorScreen(),
      ),
    );
    
    _loadFacets();
  }

  void _editFacet(ProfileFacet facet) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacetEditorScreen(existingFacet: facet),
      ),
    );
    
    _loadFacets();
  }

  Color _getFacetColor(String id) {
    switch (id) {
      case 'work': return const Color(0xFF3B82F6);
      case 'friends': return const Color(0xFFF97316);
      case 'family': return const Color(0xFFEC4899);
      case 'travel': return const Color(0xFF10B981);
      case 'creative': return const Color(0xFF8B5CF6);
      case 'gaming': return const Color(0xFFEF4444);
      default: return const Color(0xFF6B7280);
    }
  }

  Uint8List? _decodeAvatar(String avatarUrl) {
    try {
      final base64Data = avatarUrl.contains(',') 
          ? avatarUrl.split(',').last 
          : avatarUrl;
      return Uint8List.fromList(base64Decode(base64Data));
    } catch (e) {
      return null;
    }
  }
}

class _TemplateChip extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TemplateChip({
    required this.emoji,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
