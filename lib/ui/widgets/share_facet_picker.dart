/// Share Facet Picker - Phase 4c
/// 
/// Bottom sheet for selecting which facet to share via QR or link.
/// 
/// Location: lib/ui/widgets/share_facet_picker.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/profile/facet_storage.dart';

/// Result from the share facet picker
class ShareFacetResult {
  final ProfileFacet facet;
  final bool showQr;
  final bool copyLink;

  ShareFacetResult({
    required this.facet,
    this.showQr = false,
    this.copyLink = false,
  });
}

class ShareFacetPicker extends StatefulWidget {
  final String publicKey;
  final String? handle;
  
  const ShareFacetPicker({
    super.key,
    required this.publicKey,
    this.handle,
  });

  @override
  State<ShareFacetPicker> createState() => _ShareFacetPickerState();

  /// Show the picker as a modal bottom sheet
  static Future<ShareFacetResult?> show(
    BuildContext context, {
    required String publicKey,
    String? handle,
  }) {
    return showModalBottomSheet<ShareFacetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ShareFacetPicker(
        publicKey: publicKey,
        handle: handle,
      ),
    );
  }
}

class _ShareFacetPickerState extends State<ShareFacetPicker> {
  final _storage = FacetStorage();
  List<ProfileFacet> _facets = [];
  ProfileFacet? _selectedFacet;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFacets();
  }

  Future<void> _loadFacets() async {
    try {
      await _storage.initialize();
      final facets = await _storage.getAllFacets();
      final defaultFacet = await _storage.getDefaultFacet();
      setState(() {
        _facets = facets;
        _selectedFacet = defaultFacet ?? (facets.isNotEmpty ? facets.first : null);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF161B22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Text('🔗', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Share Your Identity',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text(
                          'Choose which profile to share',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Facet List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _facets.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _facets.length,
                          itemBuilder: (context, index) => _buildFacetOption(_facets[index]),
                        ),
            ),
            
            // Actions
            if (_selectedFacet != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, ShareFacetResult(
                            facet: _selectedFacet!,
                            copyLink: true,
                          )),
                          icon: const Icon(Icons.copy),
                          label: const Text('COPY LINK'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context, ShareFacetResult(
                            facet: _selectedFacet!,
                            showQr: true,
                          )),
                          icon: const Icon(Icons.qr_code),
                          label: const Text('SHOW QR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('👤', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          const Text('Default Profile', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Create facets in Settings to share\ndifferent profiles with different people.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildFacetOption(ProfileFacet facet) {
    final isSelected = _selectedFacet?.id == facet.id;
    final color = _getFacetColor(facet.id);
    
    return InkWell(
      onTap: () => setState(() => _selectedFacet = facet),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            // Radio
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : Colors.white38,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withOpacity(0.2),
              backgroundImage: facet.avatarUrl != null
                  ? MemoryImage(base64Decode(facet.avatarUrl!.split(',').last))
                  : null,
              child: facet.avatarUrl == null
                  ? Text(facet.emoji, style: const TextStyle(fontSize: 22))
                  : null,
            ),
            const SizedBox(width: 12),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        facet.label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (facet.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                  if (facet.displayName != null)
                    Text(
                      facet.displayName!,
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  if (facet.bio != null)
                    Text(
                      facet.bio!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
}
