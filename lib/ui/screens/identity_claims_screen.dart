/// Identity Claims Screen - Cross-Platform Verification Hub
///
/// Unified screen for claiming and verifying external platform identities.
/// Follows the same UX pattern as OrgRegistrationScreen (form → verify → success).
///
/// Flow:
///   1. User selects a platform to claim
///   2. User enters their username on that platform
///   3. Server generates verification code
///   4. User places code on external platform (tweet, bio, gist, DNS TXT)
///   5. User taps "Verify" → server checks
///   6. On success → claim added to id@ facet
///
/// Location: lib/ui/screens/identity_claims_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/gns/identity_wallet.dart';
// Import: identity_claim.dart (the model we created)

// ============================================================
// PLATFORM DEFINITION (inline for now, matches identity_claim.dart)
// ============================================================

class ClaimPlatformInfo {
  final String id;
  final String name;
  final String icon;
  final Color color;
  final String placeholder;
  final String description;

  const ClaimPlatformInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.placeholder,
    required this.description,
  });
}

const _platforms = [
  ClaimPlatformInfo(
    id: 'twitter',
    name: 'X / Twitter',
    icon: '𝕏',
    color: Color(0xFF000000),
    placeholder: 'username (without @)',
    description: 'Post a tweet with your verification code',
  ),
  ClaimPlatformInfo(
    id: 'instagram',
    name: 'Instagram',
    icon: '📸',
    color: Color(0xFFE4405F),
    placeholder: 'username',
    description: 'Add verification code to your bio',
  ),
  ClaimPlatformInfo(
    id: 'tiktok',
    name: 'TikTok',
    icon: '🎵',
    color: Color(0xFF010101),
    placeholder: 'username (without @)',
    description: 'Add verification code to your bio',
  ),
  ClaimPlatformInfo(
    id: 'youtube',
    name: 'YouTube',
    icon: '▶️',
    color: Color(0xFFFF0000),
    placeholder: 'channel name or @handle',
    description: 'Add code to channel description',
  ),
  ClaimPlatformInfo(
    id: 'github',
    name: 'GitHub',
    icon: '🐙',
    color: Color(0xFF181717),
    placeholder: 'username',
    description: 'Create a public gist with the code',
  ),
  ClaimPlatformInfo(
    id: 'linkedin',
    name: 'LinkedIn',
    icon: '💼',
    color: Color(0xFF0A66C2),
    placeholder: 'profile slug (from URL)',
    description: 'Add code to your About section',
  ),
  ClaimPlatformInfo(
    id: 'domain',
    name: 'Domain',
    icon: '🌐',
    color: Color(0xFF0EA5E9),
    placeholder: 'example.com',
    description: 'DNS TXT record verification',
  ),
  ClaimPlatformInfo(
    id: 'bluesky',
    name: 'Bluesky',
    icon: '🦋',
    color: Color(0xFF0085FF),
    placeholder: 'handle.bsky.social',
    description: 'Post with your verification code',
  ),
  ClaimPlatformInfo(
    id: 'mastodon',
    name: 'Mastodon',
    icon: '🦣',
    color: Color(0xFF6364FF),
    placeholder: 'user@instance.social',
    description: 'Post a toot with the code',
  ),
];

// ============================================================
// MAIN SCREEN
// ============================================================

class IdentityClaimsScreen extends StatefulWidget {
  const IdentityClaimsScreen({super.key});

  @override
  State<IdentityClaimsScreen> createState() => _IdentityClaimsScreenState();
}

class _IdentityClaimsScreenState extends State<IdentityClaimsScreen> {
  static const _apiBase = 'https://gns-browser-production.up.railway.app';

  final _wallet = IdentityWallet();

  // State
  bool _loading = true;
  String? _handle;
  String? _publicKey;
  List<dynamic> _claims = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final handle = await _wallet.getCurrentHandle();
      final info = await _wallet.getIdentityInfo();
      final pk = _wallet.publicKey;

      // Fetch existing claims
      List<dynamic> claims = [];
      if (handle != null) {
        try {
          final response = await http.get(
            Uri.parse('$_apiBase/claims/$handle?all=true'),
            headers: {
              'x-gns-publickey': pk ?? '',
            },
          ).timeout(const Duration(seconds: 10));

          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            claims = data['data']['claims'] ?? [];
          }
        } catch (e) {
          debugPrint('Failed to load claims: $e');
        }
      }

      if (mounted) {
        setState(() {
          _handle = handle ?? info.claimedHandle ?? info.reservedHandle;
          _publicKey = pk;
          _claims = claims;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity Claims'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header
                _buildHeader(isDark),
                const SizedBox(height: 24),

                // Verified Claims
                if (_claims.any((c) => c['status'] == 'verified')) ...[
                  _buildSectionHeader('VERIFIED', Icons.verified, Colors.green),
                  const SizedBox(height: 8),
                  ..._claims
                      .where((c) => c['status'] == 'verified')
                      .map((c) => _buildClaimTile(c, isDark)),
                  const SizedBox(height: 24),
                ],

                // Pending Claims
                if (_claims.any((c) =>
                    c['status'] == 'pending' || c['status'] == 'verifying')) ...[
                  _buildSectionHeader('PENDING', Icons.hourglass_top, Colors.amber),
                  const SizedBox(height: 8),
                  ..._claims
                      .where((c) =>
                          c['status'] == 'pending' ||
                          c['status'] == 'verifying')
                      .map((c) => _buildClaimTile(c, isDark)),
                  const SizedBox(height: 24),
                ],

                // Add New Claim
                _buildSectionHeader('CLAIM A PLATFORM', Icons.add_circle_outline,
                    const Color(0xFF0EA5E9)),
                const SizedBox(height: 8),
                _buildPlatformGrid(isDark),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ==================== HEADER ====================

  Widget _buildHeader(bool isDark) {
    final verifiedCount =
        _claims.where((c) => c['status'] == 'verified').length;

    return Card(
      color: isDark ? const Color(0xFF161B22) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Identity anchor
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0EA5E9), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('🆔',
                      style: TextStyle(fontSize: 28)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'id@${_handle ?? 'you'}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$verifiedCount platform${verifiedCount == 1 ? '' : 's'} verified',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF8B949E)
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Explanation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0EA5E9).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF0EA5E9).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: Color(0xFF0EA5E9)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your GNS handle is your canonical identity. '
                      'Claimed platforms are verified attributes — '
                      'proof that one human controls all of them.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF8B949E)
                            : Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SECTION HEADERS ====================

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: color,
          ),
        ),
      ],
    );
  }

  // ==================== CLAIM TILE ====================

  Widget _buildClaimTile(dynamic claim, bool isDark) {
    final platform = _platforms.firstWhere(
      (p) => p.id == claim['platform'],
      orElse: () => _platforms.last,
    );
    final isVerified = claim['status'] == 'verified';
    final isPending = claim['status'] == 'pending' ||
        claim['status'] == 'verifying';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDark ? const Color(0xFF161B22) : Colors.white,
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: platform.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(platform.icon, style: const TextStyle(fontSize: 22)),
          ),
        ),
        title: Row(
          children: [
            Text(platform.name),
            if (isVerified) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified, size: 16, color: Colors.green),
            ],
          ],
        ),
        subtitle: Text(
          '@${claim['foreign_username']}',
          style: TextStyle(
            fontFamily: 'monospace',
            color: isDark ? const Color(0xFF8B949E) : Colors.grey[600],
          ),
        ),
        trailing: isPending
            ? TextButton(
                onPressed: () => _openVerificationFlow(claim),
                child: const Text('VERIFY'),
              )
            : isVerified
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'revoke') {
                        _revokeClaimConfirm(claim);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'revoke',
                        child: Row(
                          children: [
                            Icon(Icons.link_off, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Revoke', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  )
                : null,
      ),
    );
  }

  // ==================== PLATFORM GRID ====================

  Widget _buildPlatformGrid(bool isDark) {
    // Filter out already claimed platforms
    final claimedPlatforms =
        _claims.map((c) => c['platform'] as String).toSet();

    final available =
        _platforms.where((p) => !claimedPlatforms.contains(p.id)).toList();

    if (available.isEmpty) {
      return Card(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'All platforms claimed! 🎉',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: available.map((platform) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 48) / 2,
          child: Card(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            child: InkWell(
              onTap: () => _startClaim(platform),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: platform.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(platform.icon,
                            style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      platform.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      platform.description,
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            isDark ? const Color(0xFF8B949E) : Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ==================== CLAIM FLOW ====================

  void _startClaim(ClaimPlatformInfo platform) {
    final usernameController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ClaimInitiateSheet(
        platform: platform,
        handle: _handle ?? '',
        publicKey: _publicKey ?? '',
        apiBase: _apiBase,
        onClaimCreated: (claim) {
          Navigator.pop(context);
          _loadData(); // Refresh
          _openVerificationFlow(claim);
        },
      ),
    );
  }

  void _openVerificationFlow(dynamic claim) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VerificationSheet(
        claim: claim,
        publicKey: _publicKey ?? '',
        apiBase: _apiBase,
        onVerified: () {
          Navigator.pop(context);
          _loadData(); // Refresh
        },
      ),
    );
  }

  void _revokeClaimConfirm(dynamic claim) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Claim?'),
        content: Text(
          'Remove the verified link to @${claim['foreign_username']} on '
          '${_platforms.firstWhere((p) => p.id == claim['platform'], orElse: () => _platforms.last).name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _revokeClaim(claim);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('REVOKE'),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeClaim(dynamic claim) async {
    try {
      await http.delete(
        Uri.parse('$_apiBase/claims/${claim['id']}'),
        headers: {
          'x-gns-publickey': _publicKey ?? '',
        },
      );
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to revoke: $e')),
        );
      }
    }
  }
}

// ============================================================
// CLAIM INITIATE BOTTOM SHEET
// ============================================================

class _ClaimInitiateSheet extends StatefulWidget {
  final ClaimPlatformInfo platform;
  final String handle;
  final String publicKey;
  final String apiBase;
  final Function(dynamic claim) onClaimCreated;

  const _ClaimInitiateSheet({
    required this.platform,
    required this.handle,
    required this.publicKey,
    required this.apiBase,
    required this.onClaimCreated,
  });

  @override
  State<_ClaimInitiateSheet> createState() => _ClaimInitiateSheetState();
}

class _ClaimInitiateSheetState extends State<_ClaimInitiateSheet> {
  final _usernameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _initiateClaim() async {
    final username = _usernameController.text.trim().replaceAll('@', '');
    if (username.isEmpty) {
      setState(() => _error = 'Please enter your username');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${widget.apiBase}/claims/initiate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'platform': widget.platform.id,
          'foreign_username': username,
          'gns_handle': widget.handle,
          'public_key': widget.publicKey,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        widget.onClaimCreated(data['data']);
      } else {
        setState(() {
          _error = data['error'] ?? 'Failed to create claim';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Platform header
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.platform.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(widget.platform.icon,
                      style: const TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Claim ${widget.platform.name}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Link to @${widget.handle}',
                    style: TextStyle(
                      color:
                          isDark ? const Color(0xFF8B949E) : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Username input
          Text(
            'Your ${widget.platform.name} username',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.platform.placeholder,
              prefixIcon: const Icon(Icons.person_outline),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: isDark ? const Color(0xFF21262D) : Colors.grey[50],
              errorText: _error,
            ),
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _initiateClaim(),
          ),
          const SizedBox(height: 8),

          // Info text
          Text(
            'This may be different from your GNS handle — that\'s fine! '
            'One identity, many usernames.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF8B949E) : Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _initiateClaim,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.platform.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'CLAIM ${widget.platform.name.toUpperCase()}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// VERIFICATION BOTTOM SHEET
// ============================================================

class _VerificationSheet extends StatefulWidget {
  final dynamic claim;
  final String publicKey;
  final String apiBase;
  final VoidCallback onVerified;

  const _VerificationSheet({
    required this.claim,
    required this.publicKey,
    required this.apiBase,
    required this.onVerified,
  });

  @override
  State<_VerificationSheet> createState() => _VerificationSheetState();
}

class _VerificationSheetState extends State<_VerificationSheet> {
  bool _verifying = false;
  String? _error;
  bool _success = false;

  String get _verificationCode =>
      widget.claim['verification_code'] ?? 'loading...';
  String get _platform => widget.claim['platform'] ?? '';
  String get _foreignUsername => widget.claim['foreign_username'] ?? '';

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _verificationCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Verification code copied!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${widget.apiBase}/claims/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'claim_id': widget.claim['id'],
          'public_key': widget.publicKey,
        }),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (data['success'] == true && data['verified'] == true) {
        setState(() {
          _success = true;
          _verifying = false;
        });
        // Auto-close after showing success
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) widget.onVerified();
        });
      } else {
        setState(() {
          _error = data['error'] ?? 'Verification failed. Make sure the code is posted publicly.';
          _verifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error. Try again.';
        _verifying = false;
      });
    }
  }

  String _getInstructions() {
    switch (_platform) {
      case 'twitter':
        return 'Post a tweet containing this code:';
      case 'instagram':
        return 'Add this to your Instagram bio:';
      case 'tiktok':
        return 'Add this to your TikTok bio:';
      case 'youtube':
        return 'Add this to your channel description:';
      case 'github':
        return 'Create a public gist named "gns-verify.txt" with:';
      case 'linkedin':
        return 'Add this to your LinkedIn About section:';
      case 'domain':
        return 'Add a DNS TXT record at _gns.$_foreignUsername:';
      case 'mastodon':
        return 'Post a toot containing this code:';
      case 'bluesky':
        return 'Post containing this code:';
      default:
        return 'Place this code on your profile:';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_success) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text(
              'Verified!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '@$_foreignUsername is now linked to your GNS identity',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color:
                      isDark ? const Color(0xFF8B949E) : Colors.grey[600]),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Verify @$_foreignUsername',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Instructions
          Text(
            _getInstructions(),
            style: TextStyle(
                color: isDark ? const Color(0xFF8B949E) : Colors.grey[700]),
          ),
          const SizedBox(height: 12),

          // Verification code box
          GestureDetector(
            onTap: _copyCode,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0EA5E9).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _verificationCode,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0EA5E9),
                      ),
                    ),
                  ),
                  const Icon(Icons.copy, size: 20, color: Color(0xFF0EA5E9)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to copy • Code expires in 7 days',
            style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF484F58) : Colors.grey[400]),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Verify button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _verifying ? null : _verify,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _verifying
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Text('Checking...'),
                      ],
                    )
                  : const Text(
                      "I'VE POSTED IT — VERIFY NOW",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
            ),
          ),

          const SizedBox(height: 12),

          // Secondary action
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("I'll do this later"),
            ),
          ),
        ],
      ),
    );
  }
}
