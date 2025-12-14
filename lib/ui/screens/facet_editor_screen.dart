/// Facet Editor Screen - Phase 4c (v3)
/// 
/// Create and edit profile facets with:
/// - Auto-fill Facet ID from templates
/// - Tap outside to dismiss keyboard
/// - Avatar photo or emoji selection
/// - Bio and links management
/// 
/// Location: lib/ui/screens/facet_editor_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/profile/profile_facet.dart';
import '../../core/profile/profile_module.dart';
import '../../core/profile/facet_storage.dart';

class FacetEditorScreen extends StatefulWidget {
  final ProfileFacet? existingFacet;
  final bool isNewFromTemplate;

  const FacetEditorScreen({
    super.key,
    this.existingFacet,
    this.isNewFromTemplate = false,
  });

  @override
  State<FacetEditorScreen> createState() => _FacetEditorScreenState();
}

class _FacetEditorScreenState extends State<FacetEditorScreen> {
  final _storage = FacetStorage();
  final _formKey = GlobalKey<FormState>();
  
  final _idController = TextEditingController();
  final _labelController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  
  String _selectedEmoji = '👤';
  String? _avatarBase64;
  List<ProfileLink> _links = [];
  bool _isDefault = false;
  bool _saving = false;

  bool get _isEditing => widget.existingFacet != null && !widget.isNewFromTemplate;
  bool get _isNewFacet => widget.existingFacet == null;
  bool get _isFromTemplate => widget.existingFacet != null && widget.isNewFromTemplate;

  // Available emojis for facet
  static const _emojis = ['👤', '💼', '🎉', '👨‍👩‍👧', '✈️', '🎨', '🎮', '🏠', '💪', '📚'];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _storage.initialize();
    _loadFacet();
  }

  void _loadFacet() {
    if (widget.existingFacet != null) {
      final f = widget.existingFacet!;
      _idController.text = f.id;
      _labelController.text = f.label;
      _displayNameController.text = f.displayName ?? '';
      _bioController.text = f.bio ?? '';
      _selectedEmoji = f.emoji;
      _avatarBase64 = f.avatarUrl;
      _links = List.from(f.links);
      _isDefault = f.isDefault;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _labelController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // Dismiss keyboard when tapping outside
  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,  // <-- Dismiss keyboard on tap outside
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit Facet' : 'New Facet'),
          actions: [
            if (_isEditing && widget.existingFacet?.id != 'default')
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: _confirmDelete,
              ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('SAVE'),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Avatar Section
              _buildAvatarSection(),
              const SizedBox(height: 24),

              // Basic Info
              _buildBasicInfoSection(),
              const SizedBox(height: 24),

              // Bio
              _buildBioSection(),
              const SizedBox(height: 24),

              // Links
              _buildLinksSection(),
              const SizedBox(height: 24),

              // Default Toggle
              _buildDefaultToggle(),
              
              const SizedBox(height: 32),

              // Delete Button (for existing non-default facets)
              if (_isEditing && widget.existingFacet?.id != 'default')
                _buildDeleteButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Avatar Display
            GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF21262D),
                    backgroundImage: _avatarBase64 != null
                        ? MemoryImage(base64Decode(_avatarBase64!.contains(',') 
                            ? _avatarBase64!.split(',').last 
                            : _avatarBase64!))
                        : null,
                    child: _avatarBase64 == null
                        ? Text(_selectedEmoji, style: const TextStyle(fontSize: 40))
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF0D1117), width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Emoji Picker
            const Text(
              'Facet Emoji',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _emojis.map((emoji) => GestureDetector(
                onTap: () => setState(() => _selectedEmoji = emoji),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _selectedEmoji == emoji 
                        ? const Color(0xFF3B82F6) 
                        : const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedEmoji == emoji 
                          ? const Color(0xFF3B82F6) 
                          : const Color(0xFF30363D),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              )).toList(),
            ),
            
            // Remove Photo Button
            if (_avatarBase64 != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                label: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                onPressed: () => setState(() => _avatarBase64 = null),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BASIC INFO',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 16),
            
            // Facet ID (only for new facets, including from templates)
            if (!_isEditing) ...[
              TextFormField(
                controller: _idController,
                decoration: InputDecoration(
                  labelText: 'Facet ID',
                  hintText: 'e.g., work, friends, family',
                  helperText: 'Used in share links: gns://@you/${_idController.text.isEmpty ? "id" : _idController.text}',
                  prefixIcon: const Icon(Icons.tag),
                ),
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  if (value.length < 2) return 'At least 2 characters';
                  if (value.length > 20) return 'Maximum 20 characters';
                  if (!RegExp(r'^[a-z0-9_]+$').hasMatch(value)) {
                    return 'Lowercase letters, numbers, underscore only';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}), // Update helper text
              ),
              const SizedBox(height: 16),
            ],
            
            // Label
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g., Work, Friends, Family',
                prefixIcon: Icon(Icons.label_outline),
              ),
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Required';
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Display Name
            TextFormField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'How you want to be called',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBioSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'BIO',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                Text(
                  '${_bioController.text.length}/280',
                  style: TextStyle(
                    color: _bioController.text.length > 280 
                        ? Colors.red 
                        : const Color(0xFF6E7681),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bioController,
              decoration: const InputDecoration(
                hintText: 'Tell people about this side of you...',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              maxLength: 280,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinksSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LINKS',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  onPressed: _addLink,
                ),
              ],
            ),
            if (_links.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No links yet',
                    style: TextStyle(color: const Color(0xFF6E7681)),
                  ),
                ),
              )
            else
              ...List.generate(_links.length, (index) {
                final link = _links[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(link.icon, style: const TextStyle(fontSize: 24)),
                  title: Text(
                    link.url,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    link.type,
                    style: TextStyle(color: const Color(0xFF6E7681), fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _links.removeAt(index)),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultToggle() {
    return Card(
      child: SwitchListTile(
        title: const Text('Set as Default'),
        subtitle: const Text('Show this facet to strangers'),
        value: _isDefault,
        onChanged: (value) => setState(() => _isDefault = value),
        secondary: Icon(
          _isDefault ? Icons.star : Icons.star_border,
          color: _isDefault ? const Color(0xFF10B981) : null,
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return OutlinedButton.icon(
      onPressed: _confirmDelete,
      icon: const Icon(Icons.delete_outline, color: Colors.red),
      label: const Text('Delete This Facet', style: TextStyle(color: Colors.red)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.red),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    _dismissKeyboard();
    
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (_avatarBase64 != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );

    if (source == null) return;

    if (source == 'remove') {
      setState(() => _avatarBase64 = null);
      return;
    }

    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 80,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final extension = image.path.split('.').last.toLowerCase();
      final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
      
      setState(() {
        _avatarBase64 = 'data:$mimeType;base64,$base64Image';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  void _addLink() {
    _dismissKeyboard();
    
    final urlController = TextEditingController();
    String selectedType = 'website';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Link Type Selector
              Wrap(
                spacing: 8,
                children: ['website', 'twitter', 'linkedin', 'github'].map((type) {
                  final isSelected = selectedType == type;
                  return ChoiceChip(
                    label: Text(type),
                    selected: isSelected,
                    onSelected: (_) => setDialogState(() => selectedType = type),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  hintText: _getHintForType(selectedType),
                  prefixIcon: const Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                var url = urlController.text.trim();
                if (url.isNotEmpty) {
                  // Auto-add https:// if missing
                  if (!url.startsWith('http://') && !url.startsWith('https://')) {
                    url = 'https://$url';
                  }
                  setState(() {
                    _links.add(ProfileLink(type: selectedType, url: url));
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('ADD'),
            ),
          ],
        ),
      ),
    );
  }

  String _getHintForType(String type) {
    switch (type) {
      case 'twitter': return 'twitter.com/username';
      case 'linkedin': return 'linkedin.com/in/username';
      case 'github': return 'github.com/username';
      default: return 'https://...';
    }
  }

  void _confirmDelete() {
    _dismissKeyboard();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Facet?'),
        content: Text('Are you sure you want to delete "${_labelController.text}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              if (widget.existingFacet != null) {
                await _storage.deleteFacet(widget.existingFacet!.id);
              }
              if (mounted) Navigator.pop(context); // Close editor
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    _dismissKeyboard();
    
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final facetId = _isEditing ? widget.existingFacet!.id : _idController.text.trim().toLowerCase();
      
      // Check for duplicate ID (only for new facets)
      if (!_isEditing) {
        final existing = await _storage.getFacet(facetId);
        if (existing != null) {
          setState(() => _saving = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Facet ID "$facetId" already exists')),
            );
          }
          return;
        }
      }

      final facet = ProfileFacet(
        id: facetId,
        label: _labelController.text.trim(),
        emoji: _selectedEmoji,
        displayName: _displayNameController.text.trim().isEmpty 
            ? null 
            : _displayNameController.text.trim(),
        avatarUrl: _avatarBase64,
        bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
        links: _links,
        isDefault: _isDefault,
        createdAt: widget.existingFacet?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _storage.saveFacet(facet);
      
      if (_isDefault) {
        await _storage.setDefaultFacet(facetId);
      }

      setState(() => _saving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Facet updated!' : 'Facet created!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
