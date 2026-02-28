// ============================================================
// GNS gSITE EDITOR with LIVE PREVIEW
// ============================================================
// Location: lib/ui/gsite/gsite_editor_screen.dart
// Purpose: Edit all gSite fields with a live HTML preview
//          showing exactly what ulissy.app/@handle renders
// ============================================================
//
// Architecture:
//   Edit Tab → User modifies fields
//            → _buildGSiteJson() assembles JSON in real-time
//            → GSitePreviewRenderer.renderFromJson(json) generates HTML
//            → WebView displays the rendered page
//
// Dependencies:
//   - webview_flutter (add to pubspec.yaml)
//   - gsite_preview_renderer.dart (client-side HTML generator)
//   - identity_wallet.dart (for handle, keys, signing)
//   - gsite_service.dart (for save/validate)
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import '../../core/gns/identity_wallet.dart';
import '../../core/gsite/gsite_models.dart';
import '../../core/gsite/gsite_service.dart';
import '../../core/gsite/gsite_preview_renderer.dart';
import '../../core/theme/theme_service.dart';

// ============================================================
// MAIN EDITOR SCREEN
// ============================================================

class GSiteEditorScreen extends StatefulWidget {
  final IdentityWallet wallet;
  final GSite? existingGSite; // null = creating new
  final VoidCallback? onSaved;

  const GSiteEditorScreen({
    super.key,
    required this.wallet,
    this.existingGSite,
    this.onSaved,
  });

  @override
  State<GSiteEditorScreen> createState() => _GSiteEditorScreenState();
}

class _GSiteEditorScreenState extends State<GSiteEditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ---- Form Controllers ----
  final _nameController = TextEditingController();
  final _taglineController = TextEditingController();
  final _bioController = TextEditingController();
  final _statusTextController = TextEditingController();
  final _statusEmojiController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _skillInputController = TextEditingController();
  final _interestInputController = TextEditingController();

  // ---- State ----
  List<String> _skills = [];
  List<String> _interests = [];
  List<Map<String, dynamic>> _links = [];
  List<Map<String, dynamic>> _facets = [];
  bool _statusAvailable = true;
  bool _messageEnabled = true;
  bool _paymentEnabled = true;
  bool _followEnabled = true;
  bool _callEnabled = false;
  bool _saving = false;
  bool _previewNeedsRefresh = true;

  // ---- Preview ----
  WebViewController? _webViewController;
  String _previewHtml = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadExistingData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _taglineController.dispose();
    _bioController.dispose();
    _statusTextController.dispose();
    _statusEmojiController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _skillInputController.dispose();
    _interestInputController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && _previewNeedsRefresh) {
      _refreshPreview();
    }
  }

  // ============================================================
  // LOAD EXISTING DATA
  // ============================================================

  void _loadExistingData() {
    final gsite = widget.existingGSite;
    if (gsite == null) return;

    _nameController.text = gsite.name;
    _taglineController.text = gsite.tagline ?? '';
    _bioController.text = gsite.bio ?? '';

    if (gsite.location != null) {
      _cityController.text = gsite.location!.city ?? '';
      _countryController.text = gsite.location!.country ?? '';
    }

    _links = gsite.links.map((l) => l.toJson()).toList();

    if (gsite.actions.message) _messageEnabled = true;
    if (gsite.actions.payment) _paymentEnabled = true;
    if (gsite.actions.follow) _followEnabled = true;
    if (gsite.actions.call) _callEnabled = true;

    if (gsite is PersonGSite) {
      _skills = List.from(gsite.skills);
      _interests = List.from(gsite.interests);
      _facets = gsite.facets.map((f) => f.toJson()).toList();
      _statusTextController.text = gsite.statusText ?? '';
      _statusEmojiController.text = gsite.statusEmoji ?? '';
      _statusAvailable = gsite.available ?? true;
    }
  }

  // ============================================================
  // BUILD gSITE JSON (real-time from form state)
  // ============================================================

  Map<String, dynamic> _buildGSiteJson() {
    final handle = widget.wallet.currentHandle ?? 'preview';

    final json = <String, dynamic>{
      '@context': 'https://schema.gns.network/v1',
      '@type': 'Person',
      '@id': '@$handle',
      'name': _nameController.text.isNotEmpty
          ? _nameController.text
          : handle[0].toUpperCase() + handle.substring(1),
    };

    if (_taglineController.text.isNotEmpty) {
      json['tagline'] = _taglineController.text;
    }
    if (_bioController.text.isNotEmpty) {
      json['bio'] = _bioController.text;
    }

    // Avatar from wallet profile
    final profile = widget.wallet.getProfile();
    if (profile.avatarUrl != null) {
      json['avatar'] = {'url': profile.avatarUrl};
    }

    // Location
    if (_cityController.text.isNotEmpty || _countryController.text.isNotEmpty) {
      json['location'] = {
        if (_cityController.text.isNotEmpty) 'city': _cityController.text,
        if (_countryController.text.isNotEmpty) 'country': _countryController.text,
      };
    }

    // Skills, Interests
    if (_skills.isNotEmpty) json['skills'] = _skills;
    if (_interests.isNotEmpty) json['interests'] = _interests;

    // Facets
    if (_facets.isNotEmpty) json['facets'] = _facets;

    // Status
    if (_statusTextController.text.isNotEmpty || _statusEmojiController.text.isNotEmpty) {
      json['status'] = {
        if (_statusEmojiController.text.isNotEmpty) 'emoji': _statusEmojiController.text,
        if (_statusTextController.text.isNotEmpty) 'text': _statusTextController.text,
        'available': _statusAvailable,
      };
    }

    // Links
    if (_links.isNotEmpty) json['links'] = _links;

    // Actions
    json['actions'] = {
      'message': _messageEnabled,
      'payment': _paymentEnabled,
      'follow': _followEnabled,
      'call': _callEnabled,
      'share': true,
    };

    // Trust (from wallet record, read-only)
    json['trust'] = {
      'score': widget.wallet.trustScore ?? 0,
      'breadcrumbs': widget.wallet.breadcrumbCount ?? 0,
    };

    json['publicKey'] = widget.wallet.publicKey;
    json['verified'] = true;
    json['version'] = 1;
    json['language'] = 'en';
    json['signature'] = 'ed25519:preview';

    return json;
  }

  // ============================================================
  // PREVIEW
  // ============================================================

  void _refreshPreview() {
    final json = _buildGSiteJson();
    final html = GSitePreviewRenderer.renderFromJson(json);

    if (_webViewController != null) {
      _webViewController!.loadHtmlString(html);
    }

    setState(() {
      _previewHtml = html;
      _previewNeedsRefresh = false;
    });
  }

  void _markPreviewDirty() {
    _previewNeedsRefresh = true;
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _save() async {
    final handle = widget.wallet.currentHandle;
    if (handle == null || handle.isEmpty) {
      _showSnackbar('No handle claimed yet!', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final gsiteData = _buildGSiteJson();

      // Remove preview-only fields
      gsiteData.remove('publicKey');
      gsiteData.remove('verified');

      // 1. Validate
      final validation = await gsiteService.validateGSiteJson(gsiteData);
      if (!validation.valid) {
        final errors = validation.errors.map((e) => e.message).join(', ');
        _showSnackbar('Validation failed: $errors', isError: true);
        return;
      }

      // 2. Sign content
      final contentToSign = _sortedJson(gsiteData);
      final signature = await widget.wallet.signString(contentToSign);
      if (signature == null) {
        _showSnackbar('Failed to sign gSite', isError: true);
        return;
      }
      gsiteData['signature'] = 'ed25519:$signature';

      // 3. Sign auth
      final publicKey = widget.wallet.publicKey!;
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final authMessage = 'PUT:/gsite/@$handle:$timestamp';
      final authSignature = await widget.wallet.signString(authMessage);

      if (authSignature == null) {
        _showSnackbar('Failed to sign auth', isError: true);
        return;
      }

      // 4. Save
      final uri = Uri.parse(
          'https://gns-browser-production.up.railway.app/gsite/@$handle');
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-PublicKey': publicKey,
          'X-GNS-Signature': authSignature,
          'X-GNS-Timestamp': timestamp,
        },
        body: jsonEncode(gsiteData),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && json['success'] == true) {
        final version = json['version'] ?? 1;
        _showSnackbar('gSite published! 🎉 Version $version');
        widget.onSaved?.call();
        if (mounted) Navigator.pop(context);
      } else {
        _showSnackbar(json['error'] as String? ?? 'Unknown error',
            isError: true);
      }
    } catch (e) {
      _showSnackbar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit gSite'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.edit), text: 'Edit'),
            Tab(icon: Icon(Icons.visibility), text: 'Preview'),
          ],
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.upload),
              label: const Text('Publish'),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEditTab(),
          _buildPreviewTab(),
        ],
      ),
    );
  }

  // ============================================================
  // EDIT TAB
  // ============================================================

  Widget _buildEditTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Identity Header ----
        _sectionHeader('Identity', Icons.person),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'Your name',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markPreviewDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _taglineController,
          decoration: const InputDecoration(
            labelText: 'Tagline',
            hintText: 'A short description of who you are',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markPreviewDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bioController,
          decoration: const InputDecoration(
            labelText: 'Bio',
            hintText: 'Tell the world about yourself...',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 5,
          onChanged: (_) => _markPreviewDirty(),
        ),

        const SizedBox(height: 24),

        // ---- Status ----
        _sectionHeader('Status', Icons.circle, color: Colors.green),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: _statusEmojiController,
                decoration: const InputDecoration(
                  labelText: 'Emoji',
                  border: OutlineInputBorder(),
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20),
                onChanged: (_) => _markPreviewDirty(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _statusTextController,
                decoration: const InputDecoration(
                  labelText: 'Status text',
                  hintText: 'What are you up to?',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _markPreviewDirty(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Available'),
          subtitle: const Text('Show as available for contact'),
          value: _statusAvailable,
          onChanged: (v) {
            setState(() => _statusAvailable = v);
            _markPreviewDirty();
          },
          contentPadding: EdgeInsets.zero,
        ),

        const SizedBox(height: 24),

        // ---- Location ----
        _sectionHeader('Location', Icons.location_on),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'City',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _markPreviewDirty(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _countryController,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _markPreviewDirty(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // ---- Skills ----
        _sectionHeader('Skills', Icons.code),
        const SizedBox(height: 8),
        _buildChipInput(
          controller: _skillInputController,
          items: _skills,
          hintText: 'Add a skill...',
          onAdd: (s) {
            setState(() => _skills.add(s));
            _markPreviewDirty();
          },
          onRemove: (i) {
            setState(() => _skills.removeAt(i));
            _markPreviewDirty();
          },
        ),

        const SizedBox(height: 24),

        // ---- Interests ----
        _sectionHeader('Interests', Icons.favorite_border),
        const SizedBox(height: 8),
        _buildChipInput(
          controller: _interestInputController,
          items: _interests,
          hintText: 'Add an interest...',
          onAdd: (s) {
            setState(() => _interests.add(s));
            _markPreviewDirty();
          },
          onRemove: (i) {
            setState(() => _interests.removeAt(i));
            _markPreviewDirty();
          },
        ),

        const SizedBox(height: 24),

        // ---- Links ----
        _sectionHeader('Links', Icons.link),
        const SizedBox(height: 8),
        ..._links.asMap().entries.map((entry) => _buildLinkTile(entry.key, entry.value)),
        OutlinedButton.icon(
          onPressed: _addLink,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Link'),
        ),

        const SizedBox(height: 24),

        // ---- Actions ----
        _sectionHeader('Action Buttons', Icons.touch_app),
        const SizedBox(height: 4),
        Text(
          'Choose which action buttons appear on your gSite',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        _buildActionToggle('Message', Icons.mail, _messageEnabled, (v) {
          setState(() => _messageEnabled = v);
          _markPreviewDirty();
        }),
        _buildActionToggle('Pay via GNS', Icons.payment, _paymentEnabled, (v) {
          setState(() => _paymentEnabled = v);
          _markPreviewDirty();
        }),
        _buildActionToggle('Follow', Icons.person_add, _followEnabled, (v) {
          setState(() => _followEnabled = v);
          _markPreviewDirty();
        }),
        _buildActionToggle('Call', Icons.phone, _callEnabled, (v) {
          setState(() => _callEnabled = v);
          _markPreviewDirty();
        }),

        const SizedBox(height: 24),

        // ---- Facets ----
        _sectionHeader('Facets', Icons.layers),
        const SizedBox(height: 4),
        Text(
          'Identity facets visible on your public gSite',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        ..._facets.asMap().entries.map((entry) => _buildFacetTile(entry.key, entry.value)),
        OutlinedButton.icon(
          onPressed: _addFacet,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Facet'),
        ),

        const SizedBox(height: 32),

        // ---- Preview Hint ----
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Switch to the Preview tab to see exactly how your page will look at ulissy.app/@${widget.wallet.currentHandle ?? 'handle'}',
                  style: TextStyle(fontSize: 13, color: Colors.blue[800]),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================================
  // PREVIEW TAB
  // ============================================================

  Widget _buildPreviewTab() {
    return Column(
      children: [
        // URL bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.lock, size: 14, color: Colors.green[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    'ulissy.app/@${widget.wallet.currentHandle ?? 'handle'}',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _refreshPreview,
                tooltip: 'Refresh preview',
              ),
            ],
          ),
        ),

        // WebView
        Expanded(
          child: _buildWebView(),
        ),
      ],
    );
  }

  Widget _buildWebView() {
    final json = _buildGSiteJson();
    final html = GSitePreviewRenderer.renderFromJson(json);

    return Builder(
      builder: (context) {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(const Color(0xFFFAFAF8))
          ..loadHtmlString(html);

        _webViewController = controller;

        return WebViewWidget(controller: controller);
      },
    );
  }

  // ============================================================
  // REUSABLE WIDGETS
  // ============================================================

  Widget _sectionHeader(String title, IconData icon,
      {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildChipInput({
    required TextEditingController controller,
    required List<String> items,
    required String hintText,
    required Function(String) onAdd,
    required Function(int) onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items.asMap().entries.map((entry) {
              return Chip(
                label: Text(entry.value, style: const TextStyle(fontSize: 13)),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => onRemove(entry.key),
                backgroundColor: Colors.blue.withOpacity(0.08),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        if (items.isNotEmpty) const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (value) {
                  final v = value.trim();
                  if (v.isNotEmpty) {
                    onAdd(v);
                    controller.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle),
              color: AppTheme.primary,
              onPressed: () {
                final v = controller.text.trim();
                if (v.isNotEmpty) {
                  onAdd(v);
                  controller.clear();
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLinkTile(int index, Map<String, dynamic> link) {
    final type = link['type'] as String? ?? 'website';
    final url = link['url'] as String? ?? link['handle'] as String? ?? '';
    final iconMap = {
      'website': Icons.language,
      'github': Icons.code,
      'linkedin': Icons.work,
      'twitter': Icons.alternate_email,
      'x': Icons.alternate_email,
      'medium': Icons.article,
      'instagram': Icons.camera_alt,
      'youtube': Icons.play_circle,
      'email': Icons.email,
    };

    return ListTile(
      leading: Icon(iconMap[type] ?? Icons.link, size: 22),
      title: Text(url, style: const TextStyle(fontSize: 14)),
      subtitle: Text(type, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18),
        onPressed: () {
          setState(() => _links.removeAt(index));
          _markPreviewDirty();
        },
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
    );
  }

  Widget _buildActionToggle(
      String label, IconData icon, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      title: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
      value: value,
      onChanged: (v) => onChanged(v),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
    );
  }

  Widget _buildFacetTile(int index, Map<String, dynamic> facet) {
    return ListTile(
      leading: Text(_facetIcon(facet['id'] as String? ?? ''),
          style: const TextStyle(fontSize: 20)),
      title: Text(facet['name'] as String? ?? '',
          style: const TextStyle(fontSize: 14)),
      subtitle: Text(facet['id'] as String? ?? '',
          style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Colors.grey[500])),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (facet['public'] != false)
            const Icon(Icons.visibility, size: 16, color: Colors.green)
          else
            const Icon(Icons.visibility_off, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              setState(() => _facets.removeAt(index));
              _markPreviewDirty();
            },
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
    );
  }

  String _facetIcon(String id) {
    if (id.startsWith('dix@')) return '📝';
    if (id.startsWith('home@')) return '🏠';
    if (id.startsWith('pay@')) return '💳';
    if (id.startsWith('email@')) return '✉';
    if (id.startsWith('work@')) return '💼';
    if (id.startsWith('personal@')) return '👤';
    return '📎';
  }

  // ============================================================
  // DIALOGS
  // ============================================================

  void _addLink() {
    final typeController = TextEditingController(text: 'website');
    final urlController = TextEditingController();

    final linkTypes = [
      'website', 'github', 'linkedin', 'twitter', 'x',
      'medium', 'instagram', 'youtube', 'email', 'mastodon',
      'telegram', 'discord',
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: typeController.text,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: linkTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => typeController.text = v ?? 'website',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'URL or Handle',
                hintText: 'https://... or username',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                final isUrl =
                    url.startsWith('http://') || url.startsWith('https://');
                setState(() {
                  _links.add({
                    'type': typeController.text,
                    if (isUrl) 'url': url else 'handle': url,
                  });
                });
                _markPreviewDirty();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addFacet() {
    final nameController = TextEditingController();
    final idController = TextEditingController();
    bool isPublic = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Facet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Work, Personal',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idController,
                decoration: InputDecoration(
                  labelText: 'Facet ID',
                  hintText:
                      'e.g. work@${widget.wallet.currentHandle ?? 'handle'}',
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Public'),
                value: isPublic,
                onChanged: (v) => setDialogState(() => isPublic = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty &&
                    idController.text.isNotEmpty) {
                  setState(() {
                    _facets.add({
                      'name': nameController.text,
                      'id': idController.text,
                      'public': isPublic,
                    });
                  });
                  _markPreviewDirty();
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _sortedJson(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data);
    copy.remove('signature');
    return _sortedJsonEncode(copy);
  }

  String _sortedJsonEncode(dynamic obj) {
    if (obj == null || obj is! Map && obj is! List) return jsonEncode(obj);
    if (obj is List) return '[${obj.map(_sortedJsonEncode).join(',')}]';
    final map = obj as Map<String, dynamic>;
    final keys = map.keys.toList()..sort();
    return '{${keys.map((k) => '"$k":${_sortedJsonEncode(map[k])}').join(',')}}';
  }
}
