/// Credential Approval Sheet
///
/// Bottom sheet shown when the Chrome extension requests credentials.
/// Shows domain, matching saved accounts, and Approve / Deny buttons.
///
/// Location: lib/ui/vault/credential_approval_sheet.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/vault/gns_vault_service.dart';
import '../../core/vault/gns_channel_service.dart';
import '../../core/branding/branding.dart';

/// Show when a credential_request arrives from the Chrome extension.
/// Auto-dismisses after [autoDismissTimeout] if user doesn't respond.
Future<void> showCredentialApprovalSheet(
  BuildContext context, {
  required CredentialRequest request,
  required GnsVaultService vault,
  required GnsChannelService channel,
  Duration autoDismissTimeout = const Duration(seconds: 30),
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CredentialApprovalSheet(
      request: request,
      vault: vault,
      channel: channel,
      autoDismissTimeout: autoDismissTimeout,
    ),
  );
}

class CredentialApprovalSheet extends StatefulWidget {
  final CredentialRequest request;
  final GnsVaultService vault;
  final GnsChannelService channel;
  final Duration autoDismissTimeout;

  const CredentialApprovalSheet({
    super.key,
    required this.request,
    required this.vault,
    required this.channel,
    required this.autoDismissTimeout,
  });

  @override
  State<CredentialApprovalSheet> createState() => _CredentialApprovalSheetState();
}

class _CredentialApprovalSheetState extends State<CredentialApprovalSheet> {
  List<VaultCredential> _matches = [];
  VaultCredential? _selected;
  bool _loading = true;
  int _secondsLeft = 30;
  late final _timer = _startCountdown();

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.autoDismissTimeout.inSeconds;
    _loadMatches();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Timer _startCountdown() {
    return Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _deny();
      }
    });
  }

  Future<void> _loadMatches() async {
    final matches = await widget.vault.getForDomain(widget.request.domain);
    if (!mounted) return;

    // Pre-select if hint matches or only one result
    VaultCredential? pre;
    if (widget.request.usernameHint != null) {
      pre = matches.where(
        (c) => c.username.toLowerCase() ==
               widget.request.usernameHint!.toLowerCase()
      ).firstOrNull;
    }
    pre ??= matches.length == 1 ? matches.first : null;

    setState(() {
      _matches  = matches;
      _selected = pre;
      _loading  = false;
    });
  }

  void _approve() {
    if (_selected == null) return;
    _timer.cancel();

    widget.channel.sendCredentialResponse(
      requestId: widget.request.requestId,
      domain:    widget.request.domain,
      username:  _selected!.username,
      password:  _selected!.password,
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('Sent to ${widget.request.domain}'),
          ]),
          backgroundColor: GnsBranding.primaryGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _deny() {
    _timer.cancel();
    widget.channel.sendCredentialResponse(
      requestId: widget.request.requestId,
      domain:    widget.request.domain,
      denied:    true,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              _buildHeader(isDark),
              const SizedBox(height: 20),

              // Body
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                )
              else if (_matches.isEmpty)
                _buildNoMatch()
              else
                _buildCredentialList(isDark),

              const SizedBox(height: 24),

              // Action buttons
              _buildActions(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      children: [
        // Site favicon placeholder
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: GnsBranding.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.language,
              color: GnsBranding.primaryBlue, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.request.domain,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (widget.request.pageTitle != null)
                Text(
                  widget.request.pageTitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        // Countdown ring
        SizedBox(
          width: 40, height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _secondsLeft / widget.autoDismissTimeout.inSeconds,
                strokeWidth: 3,
                backgroundColor: Colors.grey.withOpacity(0.2),
                color: _secondsLeft > 10
                    ? GnsBranding.primaryBlue
                    : Colors.red,
              ),
              Text(
                '$_secondsLeft',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoMatch() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No saved passwords for ${widget.request.domain}.\n'
              'Save one in your GNS Vault first.',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialList(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose an account',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...  _matches.map((cred) => _buildCredentialTile(cred, isDark)),
      ],
    );
  }

  Widget _buildCredentialTile(VaultCredential cred, bool isDark) {
    final isSelected = _selected?.id == cred.id;
    return GestureDetector(
      onTap: () => setState(() => _selected = cred),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? GnsBranding.primaryBlue.withOpacity(0.08)
              : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? GnsBranding.primaryBlue
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_outline,
              size: 20,
              color: isSelected ? GnsBranding.primaryBlue : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cred.username,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    '••••••••',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: GnsBranding.primaryBlue, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(bool isDark) {
    final canApprove = _selected != null;

    return Row(
      children: [
        // Deny
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _deny,
            icon: const Icon(Icons.block, size: 18),
            label: const Text('Deny'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Approve
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: canApprove ? _approve : null,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send to Browser'),
            style: FilledButton.styleFrom(
              backgroundColor: GnsBranding.primaryBlue,
              disabledBackgroundColor: Colors.grey.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
