/// Profile Editor Screen
/// 
/// Edit profile information (name, bio, avatar, links).
/// 
/// Location: lib/ui/profile/profile_editor_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/profile/profile_service.dart';
import '../../core/profile/profile_module.dart';
import '../../core/theme/theme_service.dart';
import '../screens/gns_token_screen.dart';

// ==================== PROFILE EDITOR SCREEN ====================

class ProfileEditorScreen extends StatefulWidget {
  final IdentityWallet wallet;
  final ProfileService profileService;
  final VoidCallback? onSaved;

  const ProfileEditorScreen({
    super.key,
    required this.wallet,
    required this.profileService,
    this.onSaved,
  });

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  String? _avatarUrl;
  bool _locationPublic = false;
  int _locationResolution = 7;
  List<ProfileLink> _links = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    final profile = widget.wallet.getProfile();
    _nameController.text = profile.displayName ?? '';
    _bioController.text = profile.bio ?? '';
    _avatarUrl = profile.avatarUrl;
    _locationPublic = profile.locationPublic;
    _locationResolution = profile.locationResolution;
    _links = List.from(profile.links);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppTheme.surface(context),
                    backgroundImage: _avatarUrl != null
                        ? MemoryImage(base64Decode(_avatarUrl!.split(',').last))
                        : null,
                    child: _avatarUrl == null
                        ? Icon(Icons.person, size: 50, color: AppTheme.textMuted(context))
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.background(context), width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Tap to change photo',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Display Name', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: 'Your name'),
          ),
          const SizedBox(height: 24),
          const Text('Bio', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _bioController,
            decoration: const InputDecoration(hintText: 'Tell us about yourself'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Links', style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: _addLink,
              ),
            ],
          ),
          ..._links.asMap().entries.map((entry) => ListTile(
            leading: Text(entry.value.icon, style: const TextStyle(fontSize: 20)),
            title: Text(entry.value.url),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _links.removeAt(entry.key)),
            ),
          )),
          const SizedBox(height: 24),
          const Text('Privacy', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Show location region'),
                  subtitle: const Text('Let others see your general area'),
                  value: _locationPublic,
                  onChanged: (v) => setState(() => _locationPublic = v),
                ),
                if (_locationPublic)
                  ListTile(
                    title: const Text('Location precision'),
                    trailing: DropdownButton<int>(
                      value: _locationResolution,
                      items: LocationPrivacy.resolutionLabels.entries
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _locationResolution = v!),
                    ),
                  ),
              ],
            ),
          ),
          
          // ==================== GNS TOKENS SECTION ====================
          const SizedBox(height: 24),
          const Text('Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4CAF50), Color(0xFF2196F3)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text('G', style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  )),
                ),
              ),
              title: const Text('GNS Tokens'),
              subtitle: const Text('View balance and claim tokens'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GnsTokenScreen()),
              ),
            ),
          ),
          // ==================== END GNS TOKENS ====================
          
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.error),
              title: const Text('Remove Photo', style: TextStyle(color: AppTheme.error)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    if (source == 'remove') {
      setState(() => _avatarUrl = null);
      return;
    }

    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final extension = image.path.split('.').last.toLowerCase();
      final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
      
      setState(() {
        _avatarUrl = 'data:$mimeType;base64,$base64Image';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📷 Photo selected! Tap SAVE to keep it.'),
            backgroundColor: AppTheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  void _addLink() {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Link'),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(hintText: 'https://...'),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                setState(() {
                  _links.add(ProfileLink(type: 'website', url: url));
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final profile = ProfileData(
      displayName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
      avatarUrl: _avatarUrl,
      links: _links,
      locationPublic: _locationPublic,
      locationResolution: _locationResolution,
    );

    final result = await widget.profileService.updateProfile(profile);

    setState(() => _saving = false);

    if (result.success) {
      widget.onSaved?.call();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Profile saved')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Save failed')),
      );
    }
  }
}