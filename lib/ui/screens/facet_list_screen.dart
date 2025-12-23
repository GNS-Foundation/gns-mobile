/// Facet List Screen - Updated for Meta-Identity Architecture
/// 
/// Displays all profile facets with me@ first.
/// Includes broadcast templates (DIX) and IoT (Home).
/// Shows facet type badges.
/// 
/// Location: lib/ui/screens/facet_list_screen.dart

import 'package:flutter/material.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/profile/facet_storage.dart';
import '../../core/theme/theme_service.dart';
import '../../core/gns/identity_wallet.dart';
import 'facet_editor_screen.dart';
import 'home_facet_screen.dart';
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
          : _buildFacetList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddFacetSheet,
        icon: const Icon(Icons.add),
        label: const Text('ADD FACET'),
        backgroundColor: AppTheme.primary,
      ),
    );
  }

  Widget _buildFacetList() {
    // Separate by type
    final defaultFacet = _facets.where((f) => f.isDefaultPersonal).toList();
    final broadcastFacets = _facets.where((f) => f.isBroadcast).toList();
    final iotFacets = _facets.where((f) => f.id == 'home').toList();
    final customFacets = _facets.where((f) => f.isCustom && f.id != 'home').toList();
    
    return RefreshIndicator(
      onRefresh: _loadFacets,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Explanation Card
          Card(
            color: AppTheme.primary.withValues(alpha: 0.1),
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
                          style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Default "me@" facet - always first
          if (defaultFacet.isNotEmpty) ...[
            _buildSectionHeader('DEFAULT FACET', Icons.person, AppTheme.primary),
            const SizedBox(height: 8),
            ...defaultFacet.map((facet) => _buildFacetCard(facet)),
            const SizedBox(height: 16),
          ],

          // Broadcast facets (DIX, etc.)
          if (broadcastFacets.isNotEmpty) ...[
            _buildSectionHeader('BROADCAST CHANNELS', Icons.campaign, const Color(0xFF8B5CF6)),
            const SizedBox(height: 8),
            ...broadcastFacets.map((facet) => _buildFacetCard(facet)),
            const SizedBox(height: 16),
          ],

          // IoT facets (Home)
          if (iotFacets.isNotEmpty) ...[
            _buildSectionHeader('SMART HOME', Icons.home, const Color(0xFF6366F1)),
            const SizedBox(height: 8),
            ...iotFacets.map((facet) => _buildFacetCard(facet)),
            const SizedBox(height: 16),
          ],

          // Custom facets
          if (customFacets.isNotEmpty) ...[
            _buildSectionHeader('CUSTOM FACETS', Icons.face, const Color(0xFFF97316)),
            const SizedBox(height: 8),
            ...customFacets.map((facet) => _buildFacetCard(facet)),
          ],

          // Empty state for custom facets
          if (customFacets.isEmpty && broadcastFacets.isEmpty && iotFacets.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Text(
                    'No custom facets yet',
                    style: TextStyle(color: AppTheme.textSecondary(context)),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _showAddFacetSheet,
                    icon: const Icon(Icons.add),
                    label: const Text('Create your first facet'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildFacetCard(ProfileFacet facet) {
    final avatarImage = facet.avatarUrl != null ? _decodeAvatar(facet.avatarUrl!) : null;
    final color = _getFacetColor(facet);
    final isHomeFacet = facet.id == 'home';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: facet.isDefaultPersonal || facet.isBroadcast || isHomeFacet
            ? BorderSide(color: color.withValues(alpha: 0.3), width: 1)
            : BorderSide.none,
      ),
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
                backgroundColor: color.withValues(alpha: 0.2),
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
                          '#${facet.id}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildTypeBadge(facet),
                      ],
                    ),
                    if (facet.displayName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        facet.displayName!,
                        style: TextStyle(color: AppTheme.textSecondary(context)),
                      ),
                    ],
                    if (facet.bio != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        facet.bio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.textMuted(context), fontSize: 12),
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
              
              // Delete button (only for deletable facets)
              if (facet.canDelete)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: AppTheme.textMuted(context), size: 20),
                  onPressed: () => _confirmDeleteFacet(facet),
                )
              else
                const SizedBox(width: 8),
              
              Icon(Icons.chevron_right, color: AppTheme.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(ProfileFacet facet) {
    if (facet.isDefaultPersonal) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'DEFAULT',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }
    
    if (facet.isBroadcast) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign, size: 10, color: Colors.white),
            SizedBox(width: 3),
            Text(
              'BROADCAST',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      );
    }
    
    // Home/IoT badge
    if (facet.id == 'home') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors, size: 10, color: Colors.white),
            SizedBox(width: 3),
            Text(
              'IoT',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  void _showAddFacetSheet() {
    // Get list of already-used template IDs
    final usedIds = _facets.map((f) => f.id).toSet();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
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
                    color: AppTheme.border(context),
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
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
              const SizedBox(height: 20),
              
              // 🏠 SMART HOME Section
              if (!usedIds.contains('home')) ...[
                Text(
                  'SMART HOME',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF6366F1),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                _TemplateChip(
                  emoji: '🏠',
                  label: 'Home',
                  subtitle: 'IoT device control',
                  color: const Color(0xFF6366F1),
                  isIoT: true,
                  onTap: () => _createFromTemplate('home', FacetType.custom),
                ),
                const SizedBox(height: 16),
              ],
              
              // Broadcast Templates Section
              if (!usedIds.contains('dix')) ...[
                Text(
                  'BROADCAST CHANNELS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF8B5CF6),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                _TemplateChip(
                  emoji: '🎵',
                  label: 'DIX',
                  subtitle: 'Public broadcasting',
                  color: const Color(0xFF8B5CF6),
                  isBroadcast: true,
                  onTap: () => _createFromTemplate('dix', FacetType.broadcast),
                ),
                const SizedBox(height: 16),
              ],
              
              // Personal Facets Section
              Text(
                'PERSONAL FACETS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFF97316),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              
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
                      onTap: () => _createFromTemplate('work', FacetType.custom),
                    ),
                  if (!usedIds.contains('friends'))
                    _TemplateChip(
                      emoji: '🎉',
                      label: 'Friends',
                      color: const Color(0xFFF97316),
                      onTap: () => _createFromTemplate('friends', FacetType.custom),
                    ),
                  if (!usedIds.contains('family'))
                    _TemplateChip(
                      emoji: '👨‍👩‍👧',
                      label: 'Family',
                      color: const Color(0xFFEC4899),
                      onTap: () => _createFromTemplate('family', FacetType.custom),
                    ),
                  if (!usedIds.contains('travel'))
                    _TemplateChip(
                      emoji: '✈️',
                      label: 'Travel',
                      color: const Color(0xFF10B981),
                      onTap: () => _createFromTemplate('travel', FacetType.custom),
                    ),
                  if (!usedIds.contains('creative'))
                    _TemplateChip(
                      emoji: '🎨',
                      label: 'Creative',
                      color: const Color(0xFF8B5CF6),
                      onTap: () => _createFromTemplate('creative', FacetType.custom),
                    ),
                  if (!usedIds.contains('gaming'))
                    _TemplateChip(
                      emoji: '🎮',
                      label: 'Gaming',
                      color: const Color(0xFFEF4444),
                      onTap: () => _createFromTemplate('gaming', FacetType.custom),
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

  void _createFromTemplate(String templateId, FacetType type) async {
    Navigator.pop(context); // Close bottom sheet
    
    // Special handling for home facet - create and open IoT screen
    if (templateId == 'home') {
      final homeFacet = ProfileFacet(
        id: 'home',
        label: 'Home',
        emoji: '🏠',
        bio: 'Smart home control',
      );
      await _storage.saveFacet(homeFacet);
      _loadFacets();
      _openHomeFacet();
      return;
    }
    
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
      case 'dix':
        templateFacet = ProfileFacet.dixTemplate();
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
    // Special handling for home facet - open IoT control screen
    if (facet.id == 'home') {
      _openHomeFacet();
      return;
    }
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacetEditorScreen(existingFacet: facet),
      ),
    );
    
    _loadFacets();
  }

  void _openHomeFacet() async {
    final wallet = IdentityWallet();
    final info = await wallet.getIdentityInfo();
    
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HomeFacetScreen(
            userPublicKey: info.publicKey ?? '',
            userHandle: info.claimedHandle ?? info.reservedHandle,
          ),
        ),
      );
    }
  }

  void _confirmDeleteFacet(ProfileFacet facet) {
    if (!facet.canDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete this facet')),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${facet.label}?'),
        content: Text(
          'This will permanently delete the ${facet.id}@ facet. '
          'Any messages sent with this facet will remain but the facet cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _storage.deleteFacet(facet.id);
              _loadFacets();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${facet.label} deleted')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  Color _getFacetColor(ProfileFacet facet) {
    if (facet.isDefaultPersonal) return AppTheme.primary;
    if (facet.isBroadcast) return const Color(0xFF8B5CF6);
    if (facet.id == 'home') return const Color(0xFF6366F1);
    
    switch (facet.id) {
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
  final String? subtitle;
  final Color color;
  final bool isBroadcast;
  final bool isIoT;
  final VoidCallback onTap;

  const _TemplateChip({
    required this.emoji,
    required this.label,
    this.subtitle,
    required this.color,
    this.isBroadcast = false,
    this.isIoT = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isBroadcast || isIoT) {
      // Full-width chip for broadcast/IoT
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isIoT
                  ? [color.withValues(alpha: 0.15), const Color(0xFF10B981).withValues(alpha: 0.1)]
                  : [color.withValues(alpha: 0.15), const Color(0xFFEC4899).withValues(alpha: 0.1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: isIoT
                                ? LinearGradient(colors: [color, const Color(0xFF10B981)])
                                : LinearGradient(colors: [color, const Color(0xFFEC4899)]),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isIoT ? Icons.sensors : Icons.campaign,
                                size: 10,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                isIoT ? 'IoT' : 'BROADCAST',
                                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: AppTheme.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.add_circle, color: color),
            ],
          ),
        ),
      );
    }
    
    // Regular chip
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
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
