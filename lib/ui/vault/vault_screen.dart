/// GNS Vault Screen
///
/// Password manager UI — lists saved credentials, add/edit/delete,
/// and shows real-time connection status with Chrome extension.
///
/// Location: lib/ui/vault/vault_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/vault/gns_vault_service.dart';
import '../../core/vault/gns_channel_service.dart';
import '../../core/branding/branding.dart';
import 'credential_approval_sheet.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _vault   = GnsVaultService();
  final _channel = GnsChannelService();

  List<VaultCredential> _credentials = [];
  ChannelConnectionState _channelState = ChannelConnectionState.disconnected;
  bool _loading = true;
  String _search = '';

  late final StreamSubscription _channelStateSub;
  late final StreamSubscription _credentialRequestSub;

  @override
  void initState() {
    super.initState();
    _load();

    _channelState = _channel.state;
    _channelStateSub = _channel.stateStream.listen((s) {
      if (mounted) setState(() => _channelState = s);
    });

    // Listen for incoming credential requests from Chrome extension
    _credentialRequestSub = _channel.credentialRequests.listen((req) {
      if (mounted) {
        showCredentialApprovalSheet(
          context,
          request: req,
          vault:   _vault,
          channel: _channel,
        );
      }
    });
  }

  @override
  void dispose() {
    _channelStateSub.cancel();
    _credentialRequestSub.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final creds = await _vault.getAll();
    if (mounted) {
      setState(() {
        _credentials = creds;
        _loading = false;
      });
    }
  }

  List<VaultCredential> get _filtered {
    if (_search.isEmpty) return _credentials;
    final q = _search.toLowerCase();
    return _credentials.where((c) =>
      c.domain.contains(q) || c.username.contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('GNS Vault',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        actions: [
          // Chrome extension connection indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _ChannelStatusBadge(state: _channelState),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search bar
                _buildSearchBar(isDark),

                // Credential list
                Expanded(
                  child: _credentials.isEmpty
                      ? _buildEmpty(isDark)
                      : _filtered.isEmpty
                          ? _buildNoResults()
                          : _buildList(isDark),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCredentialSheet(context),
        backgroundColor: GnsBranding.primaryBlue,
        icon: const Icon(Icons.add),
        label: const Text('Add password'),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Search by site or username...',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: isDark
              ? Colors.white.withOpacity(0.07)
              : Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 64,
              color: Colors.grey.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text('No passwords saved yet',
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              )),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your first password.\nChrome extension will fill them automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Text('No results for "$_search"',
          style: TextStyle(color: Colors.grey.shade500)),
    );
  }

  Widget _buildList(bool isDark) {
    // Group by first letter of domain
    final grouped = <String, List<VaultCredential>>{};
    for (final c in _filtered) {
      final key = c.domain[0].toUpperCase();
      grouped.putIfAbsent(key, () => []).add(c);
    }
    final keys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: keys.fold(0, (sum, k) => sum + 1 + grouped[k]!.length),
      itemBuilder: (context, index) {
        int i = 0;
        for (final key in keys) {
          if (index == i) {
            // Section header
            return Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(key,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500, letterSpacing: 0.8,
                ),
              ),
            );
          }
          i++;
          for (final cred in grouped[key]!) {
            if (index == i) {
              return _CredentialTile(
                credential: cred,
                isDark: isDark,
                onEdit:   () => _showEditSheet(context, cred),
                onDelete: () => _confirmDelete(context, cred),
              );
            }
            i++;
          }
        }
        return null;
      },
    );
  }

  // ── Add / Edit ──────────────────────────────────────────────────────────────

  Future<void> _showAddCredentialSheet(BuildContext context) async {
    await _showCredentialForm(context, null);
    await _load();
  }

  Future<void> _showEditSheet(BuildContext context, VaultCredential cred) async {
    await _showCredentialForm(context, cred);
    await _load();
  }

  Future<void> _showCredentialForm(BuildContext ctx, VaultCredential? existing) async {
    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CredentialFormSheet(
        existing: existing,
        vault: _vault,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, VaultCredential cred) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete password?'),
        content: Text('Remove ${cred.username} at ${cred.domain}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _vault.deleteCredential(cred.id);
      await _load();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Channel status badge
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelStatusBadge extends StatelessWidget {
  final ChannelConnectionState state;
  const _ChannelStatusBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (state) {
      ChannelConnectionState.connected    => (Colors.green,  Icons.extension,         'Extension connected'),
      ChannelConnectionState.connecting   => (Colors.orange, Icons.sync,               'Connecting...'),
      ChannelConnectionState.reconnecting => (Colors.orange, Icons.sync_problem,       'Reconnecting...'),
      ChannelConnectionState.disconnected => (Colors.grey,   Icons.extension_off,      'Extension offline'),
    };

    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              state == ChannelConnectionState.connected ? 'Live' : 'Offline',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Credential tile
// ─────────────────────────────────────────────────────────────────────────────

class _CredentialTile extends StatelessWidget {
  final VaultCredential credential;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CredentialTile({
    required this.credential,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2),
            ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: GnsBranding.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              credential.domain[0].toUpperCase(),
              style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold,
                color: GnsBranding.primaryBlue,
              ),
            ),
          ),
        ),
        title: Text(
          credential.domain,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          credential.username,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: credential.password));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              tooltip: 'Copy password',
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 18),
              onPressed: () => _showMenu(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () { Navigator.pop(context); onEdit(); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); onDelete(); },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit form
// ─────────────────────────────────────────────────────────────────────────────

class _CredentialFormSheet extends StatefulWidget {
  final VaultCredential? existing;
  final GnsVaultService vault;

  const _CredentialFormSheet({this.existing, required this.vault});

  @override
  State<_CredentialFormSheet> createState() => _CredentialFormSheetState();
}

class _CredentialFormSheetState extends State<_CredentialFormSheet> {
  late final _domainCtrl    = TextEditingController(text: widget.existing?.domain);
  late final _usernameCtrl  = TextEditingController(text: widget.existing?.username);
  late final _passwordCtrl  = TextEditingController(text: widget.existing?.password);
  late final _notesCtrl     = TextEditingController(text: widget.existing?.notes);

  bool _obscurePassword = true;
  bool _saving = false;

  @override
  void dispose() {
    _domainCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_domainCtrl.text.isEmpty || _usernameCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      return;
    }
    setState(() => _saving = true);

    if (widget.existing != null) {
      await widget.vault.updateCredential(
        widget.existing!.copyWith(
          domain:   _domainCtrl.text.trim(),
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text,
          notes:    _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        ),
      );
    } else {
      await widget.vault.addCredential(
        domain:   _domainCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        notes:    _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
      );
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isEdit ? 'Edit password' : 'Add password',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            _field('Site', _domainCtrl,   hint: 'github.com'),
            const SizedBox(height: 12),
            _field('Username', _usernameCtrl, hint: 'you@email.com',
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),

            // Password field with toggle
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.shade50,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _field('Notes (optional)', _notesCtrl, maxLines: 2),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: GnsBranding.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEdit ? 'Save changes' : 'Save password',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.shade50,
      ),
    );
  }
}
