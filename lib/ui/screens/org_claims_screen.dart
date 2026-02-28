/// GNS Organization Claims Screen
/// 
/// Manages all verified claims for an organization namespace.
/// Admin can add social media, legal entity, developer, and commerce claims.
/// Shows verification status, instructions, and GLUE URI.
/// 
/// Location: lib/ui/screens/org_claims_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/org/org_claim.dart';

class OrgClaimsScreen extends StatefulWidget {
  final String namespace;
  final String adminPk;
  final String organizationName;
  final String domain;

  const OrgClaimsScreen({
    super.key,
    required this.namespace,
    required this.adminPk,
    required this.organizationName,
    required this.domain,
  });

  @override
  State<OrgClaimsScreen> createState() => _OrgClaimsScreenState();
}

class _OrgClaimsScreenState extends State<OrgClaimsScreen> with SingleTickerProviderStateMixin {
  late final OrgClaimsService _service;
  late final TabController _tabController;
  
  List<OrgClaim> _claims = [];
  Map<String, List<OrgClaimType>> _claimTypes = {};
  bool _loading = true;
  String? _error;

  final _categoryTabs = ['all', 'social', 'legal', 'developer', 'commerce', 'directory', 'glue'];

  @override
  void initState() {
    super.initState();
    _service = OrgClaimsService(namespace: widget.namespace, adminPk: widget.adminPk);
    _tabController = TabController(length: _categoryTabs.length, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final claims = await _service.listClaims();
      final types = await _service.getClaimTypes();
      setState(() {
        _claims = claims;
        _claimTypes = types;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<OrgClaim> _filteredClaims(String category) {
    if (category == 'all') return _claims;
    return _claims.where((c) => c.category == category).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.namespace}@', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Organization Claims', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _categoryTabs.map((cat) {
            final info = orgClaimCategories[cat];
            final count = _filteredClaims(cat).length;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(cat == 'all' ? '📋' : (info?.icon ?? '🔗'), style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(cat == 'all' ? 'All' : (info?.name ?? cat)),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$count', style: const TextStyle(fontSize: 10)),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: Colors.red[400])))
              : TabBarView(
                  controller: _tabController,
                  children: _categoryTabs.map((cat) => _buildClaimsList(cat)).toList(),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddClaimDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Claim'),
      ),
    );
  }

  Widget _buildClaimsList(String category) {
    final claims = _filteredClaims(category);
    
    if (claims.isEmpty) {
      final info = orgClaimCategories[category];
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(category == 'all' ? '📋' : (info?.icon ?? '🔗'), style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              category == 'all' 
                  ? 'No claims yet' 
                  : 'No ${info?.name ?? category} claims',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            Text(
              category == 'all'
                  ? 'Add social media, legal identifiers, and more'
                  : info?.description ?? '',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddClaimDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Claim'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: claims.length + 1, // +1 for header
        itemBuilder: (ctx, i) {
          if (i == 0) return _buildOrgHeader();
          return _buildClaimCard(claims[i - 1]);
        },
      ),
    );
  }

  Widget _buildOrgHeader() {
    final glueClaim = _claims.where((c) => c.category == 'glue').firstOrNull;
    final verifiedCount = _claims.where((c) => c.isVerified).length;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade900, Colors.indigo.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏢', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.organizationName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${widget.namespace}@ · ${widget.domain}',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$verifiedCount verified',
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (glueClaim != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: glueClaim.claimValue));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('GLUE URI copied!'), duration: Duration(seconds: 2)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Text('🆔', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        glueClaim.claimValue,
                        style: TextStyle(
                          color: Colors.cyan[200],
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.copy, size: 14, color: Colors.white.withOpacity(0.5)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClaimCard(OrgClaim claim) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: claim.isVerified 
              ? Colors.green.withOpacity(0.3) 
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Color(claim.statusColor).withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(claim.icon, style: const TextStyle(fontSize: 22))),
        ),
        title: Row(
          children: [
            Text(
              claim.typeName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(width: 6),
            _statusBadge(claim.status),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              claim.claimValue,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontFamily: claim.category == 'legal' || claim.category == 'glue' ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (claim.enrichedData.isNotEmpty && claim.enrichedData['legal_name'] != null) ...[
              const SizedBox(height: 2),
              Text(
                claim.enrichedData['legal_name'] as String,
                style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) => _handleClaimAction(action, claim),
          itemBuilder: (ctx) => [
            if (claim.isPending)
              const PopupMenuItem(value: 'verify', child: Row(
                children: [Icon(Icons.check_circle_outline, size: 18), SizedBox(width: 8), Text('Verify')],
              )),
            if (claim.externalUrl != null)
              const PopupMenuItem(value: 'open', child: Row(
                children: [Icon(Icons.open_in_new, size: 18), SizedBox(width: 8), Text('Open Link')],
              )),
            const PopupMenuItem(value: 'copy', child: Row(
              children: [Icon(Icons.copy, size: 18), SizedBox(width: 8), Text('Copy Value')],
            )),
            if (claim.category != 'glue')
              const PopupMenuItem(value: 'revoke', child: Row(
                children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Revoke', style: TextStyle(color: Colors.red))],
              )),
          ],
        ),
        onTap: () => _showClaimDetails(claim),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'verified':
        color = Colors.green;
        label = '✓ Verified';
        break;
      case 'pending':
        color = Colors.orange;
        label = '⏳ Pending';
        break;
      case 'verifying':
        color = Colors.blue;
        label = '🔄 Verifying';
        break;
      case 'failed':
        color = Colors.red;
        label = '✗ Failed';
        break;
      default:
        color = Colors.grey;
        label = status;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  // =============================================================
  // ACTIONS
  // =============================================================

  void _handleClaimAction(String action, OrgClaim claim) async {
    switch (action) {
      case 'verify':
        _triggerVerification(claim);
        break;
      case 'open':
        // TODO: url_launcher
        Clipboard.setData(ClipboardData(text: claim.externalUrl!));
        _showSnack('URL copied — open in browser');
        break;
      case 'copy':
        Clipboard.setData(ClipboardData(text: claim.claimValue));
        _showSnack('Copied: ${claim.claimValue}');
        break;
      case 'revoke':
        _confirmRevoke(claim);
        break;
    }
  }

  Future<void> _triggerVerification(OrgClaim claim) async {
    _showSnack('Checking verification...');
    final result = await _service.verifyClaim(claim.id);
    
    if (result.verified) {
      _showSnack('✅ ${claim.typeName} verified!');
      _loadData();
    } else {
      _showSnack(result.message ?? 'Not yet verified — check DNS propagation');
    }
  }

  void _confirmRevoke(OrgClaim claim) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Claim?'),
        content: Text('Remove ${claim.typeName}: ${claim.claimValue}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await _service.revokeClaim(claim.id);
              if (ok) {
                _showSnack('Claim revoked');
                _loadData();
              } else {
                _showSnack('Failed to revoke');
              }
            },
            child: const Text('Revoke', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showClaimDetails(OrgClaim claim) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              
              // Header
              Row(
                children: [
                  Text(claim.icon, style: const TextStyle(fontSize: 36)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(claim.typeName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(claim.category.toUpperCase(), style: TextStyle(fontSize: 11, color: Colors.grey[500], letterSpacing: 1)),
                      ],
                    ),
                  ),
                  _statusBadge(claim.status),
                ],
              ),
              const SizedBox(height: 20),
              
              // Value
              _detailRow('Value', claim.claimValue, mono: true, copyable: true),
              if (claim.displayLabel != null) _detailRow('Label', claim.displayLabel!),
              if (claim.externalUrl != null) _detailRow('URL', claim.externalUrl!, copyable: true),
              if (claim.verificationMethod != null) _detailRow('Method', claim.verificationMethod!),
              if (claim.verifiedAt != null) _detailRow('Verified', claim.verifiedAt!.toLocal().toString().substring(0, 16)),
              if (claim.expiresAt != null) _detailRow('Expires', claim.expiresAt!.toLocal().toString().substring(0, 16)),
              _detailRow('Created', claim.createdAt.toLocal().toString().substring(0, 16)),
              
              // Enriched data (GLEIF, VAT, etc.)
              if (claim.enrichedData.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Enriched Data', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[400])),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    const JsonEncoder.withIndent('  ').convert(claim.enrichedData),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Actions
              if (claim.isPending) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _triggerVerification(claim);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Check Verification'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (claim.category != 'glue')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmRevoke(claim);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Revoke Claim', style: TextStyle(color: Colors.red)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool mono = false, bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontFamily: mono ? 'monospace' : null),
            ),
          ),
          if (copyable)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                _showSnack('Copied');
              },
              child: Icon(Icons.copy, size: 14, color: Colors.grey[500]),
            ),
        ],
      ),
    );
  }

  // =============================================================
  // ADD CLAIM DIALOG
  // =============================================================

  void _showAddClaimDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddClaimSheet(
        claimTypes: _claimTypes,
        onSubmit: (type, value, label) async {
          Navigator.pop(ctx);
          await _submitNewClaim(type, value, label);
        },
        namespace: widget.namespace,
      ),
    );
  }

  Future<void> _submitNewClaim(String claimType, String claimValue, String? label) async {
    _showSnack('Submitting claim...');
    
    final result = await _service.submitClaim(
      claimType: claimType,
      claimValue: claimValue,
      displayLabel: label,
    );
    
    if (result.error != null) {
      _showSnack('❌ ${result.error}');
      return;
    }
    
    if (result.claim?.isVerified == true) {
      _showSnack('✅ ${result.claim!.typeName} verified automatically!');
    } else if (result.verification != null) {
      _showVerificationInstructions(result.claim!, result.verification!);
    } else {
      _showSnack('📋 Claim submitted — pending verification');
    }
    
    _loadData();
  }

  void _showVerificationInstructions(OrgClaim claim, VerificationInstructions instructions) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(claim.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(child: Text('Verify ${claim.typeName}', style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(instructions.instructions, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              
              if (instructions.dns != null) ...[
                _instructionField('Host', instructions.dns!['host'] ?? ''),
                _instructionField('Type', instructions.dns!['type'] ?? 'TXT'),
                _instructionField('Value', instructions.dns!['value'] ?? ''),
              ],
              
              if (instructions.requiredText != null) ...[
                const Text('Add this to your profile:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                _instructionField('Text', instructions.requiredText!),
                if (instructions.alternative != null)
                  _instructionField('Or URL', instructions.alternative!),
              ],
              
              if (instructions.metaTag != null)
                _instructionField('Meta Tag', instructions.metaTag!),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }

  Widget _instructionField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              _showSnack('Copied: $label');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  ),
                  const Icon(Icons.copy, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }
}

// =============================================================
// ADD CLAIM SHEET
// =============================================================

class _AddClaimSheet extends StatefulWidget {
  final Map<String, List<OrgClaimType>> claimTypes;
  final Future<void> Function(String type, String value, String? label) onSubmit;
  final String namespace;

  const _AddClaimSheet({
    required this.claimTypes,
    required this.onSubmit,
    required this.namespace,
  });

  @override
  State<_AddClaimSheet> createState() => _AddClaimSheetState();
}

class _AddClaimSheetState extends State<_AddClaimSheet> {
  String? _selectedCategory;
  OrgClaimType? _selectedType;
  final _valueController = TextEditingController();
  final _labelController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _valueController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Add Claim', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(
              'Verify your organization\'s presence across platforms',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),

            // Step 1: Category
            if (_selectedCategory == null) ...[
              const Text('Choose category:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ...orgClaimCategories.entries
                  .where((e) => e.key != 'glue') // Can't manually add GLUE
                  .map((entry) => _categoryCard(entry.key, entry.value)),
            ],

            // Step 2: Claim Type
            if (_selectedCategory != null && _selectedType == null) ...[
              _backButton(() => setState(() => _selectedCategory = null)),
              const SizedBox(height: 12),
              Text(
                '${orgClaimCategories[_selectedCategory]?.icon ?? ''} ${orgClaimCategories[_selectedCategory]?.name ?? _selectedCategory}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...(widget.claimTypes[_selectedCategory!] ?? []).map(_claimTypeCard),
              if ((widget.claimTypes[_selectedCategory!] ?? []).isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No claim types available for this category.\nRun the database migration first.',
                    style: TextStyle(color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],

            // Step 3: Value Input
            if (_selectedType != null) ...[
              _backButton(() => setState(() => _selectedType = null)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(_selectedType!.icon ?? '🔗', style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text(_selectedType!.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              if (_selectedType!.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_selectedType!.description!, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                ),
              const SizedBox(height: 20),
              
              TextField(
                controller: _valueController,
                decoration: InputDecoration(
                  labelText: _valuePlaceholder(_selectedType!.claimType),
                  hintText: _valueHint(_selectedType!.claimType),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Display Label (optional)',
                  hintText: 'e.g. "Our official Twitter"',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 8),
              
              // Verification method info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _verificationInfo(_selectedType!),
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _selectedType!.verificationMethods.contains('api_lookup')
                              ? 'Submit & Verify'
                              : 'Submit Claim',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _categoryCard(String key, ({String name, String icon, String description}) info) {
    final count = widget.claimTypes[key]?.length ?? 0;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Text(info.icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(info.description, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            Text('$count types', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _claimTypeCard(OrgClaimType ct) {
    return GestureDetector(
      onTap: () => setState(() => _selectedType = ct),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark 
              ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Text(ct.icon ?? '🔗', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ct.displayName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                  if (ct.description != null)
                    Text(ct.description!, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _backButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.arrow_back_ios, size: 14, color: Colors.grey[500]),
          Text(' Back', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        ],
      ),
    );
  }

  String _valuePlaceholder(String type) {
    switch (type) {
      case 'twitter': return 'Twitter handle';
      case 'linkedin_company': return 'LinkedIn company slug';
      case 'instagram': return 'Instagram handle';
      case 'youtube': return 'YouTube channel handle';
      case 'tiktok': return 'TikTok handle';
      case 'facebook': return 'Facebook page name';
      case 'discord': return 'Discord invite code';
      case 'lei': return 'LEI (20 characters)';
      case 'vat_id': return 'VAT Number (with country code)';
      case 'euid': return 'EUID identifier';
      case 'duns': return 'D-U-N-S Number';
      case 'github_org': return 'GitHub organization name';
      case 'npm_org': return 'npm organization name';
      case 'google_business': return 'Google Maps CID';
      default: return 'Value';
    }
  }

  String _valueHint(String type) {
    switch (type) {
      case 'twitter': return 'ulissy_gns (without @)';
      case 'linkedin_company': return 'ulissy';
      case 'instagram': return 'ulissy_gns';
      case 'youtube': return '@ulissy';
      case 'tiktok': return 'ulissy_gns';
      case 'lei': return 'INR2EJN1ERAN0W5ZP974';
      case 'vat_id': return 'IT18315191009';
      case 'euid': return 'ITRM.18315191009';
      case 'duns': return '123456789';
      case 'rea': return 'RM-1777154';
      case 'github_org': return 'GNS-Foundation';
      default: return '';
    }
  }

  String _verificationInfo(OrgClaimType ct) {
    if (ct.verificationMethods.contains('api_lookup')) {
      return 'Will be verified automatically via API lookup';
    }
    if (ct.verificationMethods.contains('dns_txt')) {
      return 'You\'ll add a DNS TXT record to verify ownership';
    }
    if (ct.verificationMethods.contains('profile_link')) {
      return 'Add "gns:${widget.namespace}@" to your profile to verify';
    }
    if (ct.verificationMethods.contains('meta_tag')) {
      return 'Add a meta tag to your website to verify';
    }
    return 'Requires manual verification (reviewed within 48h)';
  }

  void _submit() async {
    final value = _valueController.text.trim();
    if (value.isEmpty) return;
    
    // Clean up value based on type
    String cleanValue = value;
    if (_selectedType!.claimType == 'twitter' || _selectedType!.claimType == 'instagram' || 
        _selectedType!.claimType == 'tiktok') {
      cleanValue = value.replaceAll('@', '').replaceAll(RegExp(r'https?://[^/]+/'), '');
    }
    
    setState(() => _submitting = true);
    await widget.onSubmit(
      _selectedType!.claimType,
      cleanValue,
      _labelController.text.isNotEmpty ? _labelController.text : null,
    );
    if (mounted) setState(() => _submitting = false);
  }
}
