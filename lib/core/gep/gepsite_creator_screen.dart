/// GEPSite Creator Screen
///
/// Full-screen UI for creating a GEPSite (GEP claim) at the user's
/// current location. Shows eligibility, tier selection, content editor,
/// and preview.
///
/// Location: lib/ui/gep/gepsite_creator_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/gns/identity_wallet.dart';
import '../../core/gep/gep_address.dart';
import '../../core/gep/gep_claim_service.dart';
import '../../core/theme/theme_service.dart';

class GepSiteCreatorScreen extends StatefulWidget {
  final IdentityWallet wallet;
  final double lat;
  final double lon;

  const GepSiteCreatorScreen({
    super.key,
    required this.wallet,
    required this.lat,
    required this.lon,
  });

  @override
  State<GepSiteCreatorScreen> createState() => _GepSiteCreatorScreenState();
}

class _GepSiteCreatorScreenState extends State<GepSiteCreatorScreen> {
  final _claimService = GepClaimService();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _urlController = TextEditingController();
  final _domainController = TextEditingController();

  int _resolution = 10; // Default to building-level
  ClaimTier _selectedTier = ClaimTier.visitor;
  ClaimTierEligibility? _eligibility;
  GepAddress? _gea;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  GepClaim? _result;

  @override
  void initState() {
    super.initState();
    _checkEligibility();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _urlController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  Future<void> _checkEligibility() async {
    setState(() => _loading = true);
    try {
      final eligibility = await _claimService.checkEligibility(
        lat: widget.lat,
        lon: widget.lon,
        resolution: _resolution,
      );
      final gea = GepAddress.fromLatLon(widget.lat, widget.lon, resolution: _resolution);
      setState(() {
        _eligibility = eligibility;
        _gea = gea;
        _selectedTier = eligibility.highestTier;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to check eligibility: $e';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a title for your GEPSite');
      return;
    }

    setState(() { _submitting = true; _error = null; });

    try {
      // Sign the claim with the wallet's identity key
      final dataToSign = jsonEncode({
        'lat': widget.lat,
        'lon': widget.lon,
        'resolution': _resolution,
        'tier': _selectedTier.value,
        'title': _titleController.text.trim(),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      final signature = await widget.wallet.sign(dataToSign);

      final claim = await _claimService.submitClaim(
        lat: widget.lat,
        lon: widget.lon,
        resolution: _resolution,
        tier: _selectedTier,
        claimantPk: widget.wallet.publicKey ?? '',
        breadcrumbsInCell: _eligibility?.breadcrumbsInCell ?? 0,
        uniqueDays: _eligibility?.uniqueDays ?? 0,
        title: _titleController.text.trim(),
        description: _descController.text.trim().isNotEmpty
            ? _descController.text.trim()
            : null,
        contentUrl: _urlController.text.trim().isNotEmpty
            ? _urlController.text.trim()
            : null,
        domain: _domainController.text.trim().isNotEmpty
            ? _domainController.text.trim()
            : null,
        delegationCert: _selectedTier == ClaimTier.sovereign
            ? 'org:${widget.wallet.publicKey!.substring(0, 16)}:delegation:${DateTime.now().toIso8601String()}'
            : null,
        signature: signature,
      );

      setState(() { _result = claim; _submitting = false; });
    } catch (e) {
      setState(() { _error = '$e'; _submitting = false; });
    }
  }

  void _openPhysicalWeb() {
    final url = _claimService.getPhysicalWebUrl(
      widget.lat, widget.lon, resolution: _resolution,
    );
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create GEPSite'),
        actions: [
          if (_gea != null)
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: _openPhysicalWeb,
              tooltip: 'Preview on Physical Web',
            ),
        ],
      ),
      body: _result != null ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── GEA CARD ──
          _buildGeaCard(),
          const SizedBox(height: 16),

          // ── ELIGIBILITY ──
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ))
          else ...[
            _buildEligibilityCard(),
            const SizedBox(height: 16),

            // ── RESOLUTION SELECTOR ──
            _buildResolutionSelector(),
            const SizedBox(height: 16),

            // ── TIER SELECTOR ──
            _buildTierSelector(),
            const SizedBox(height: 20),

            // ── CONTENT EDITOR ──
            _buildContentEditor(),
            const SizedBox(height: 16),

            // ── DOMAIN (optional) ──
            if (_selectedTier == ClaimTier.sovereign || _selectedTier == ClaimTier.resident)
              _buildDomainField(),

            // ── ERROR ──
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                  ),
                  child: Text(_error!, style: TextStyle(color: AppTheme.error, fontSize: 13)),
                ),
              ),

            // ── SUBMIT BUTTON ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_eligibility?.canClaim ?? false) && !_submitting ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00AEEF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _selectedTier == ClaimTier.visitor
                            ? 'POST REVIEW'
                            : 'CREATE GEPSITE',
                        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildGeaCard() {
    final gea = _gea;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00AEEF).withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00AEEF).withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('🌍', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GEP Physical Web',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF00AEEF))),
                    Text('${widget.lat.toFixed(6)}°, ${widget.lon.toFixed(6)}°',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context))),
                  ],
                ),
              ),
            ],
          ),
          if (gea != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(gea.shortDisplay,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF00AEEF))),
                  ),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: gea.encoded));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('GEA copied'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Icon(Icons.copy, size: 16, color: AppTheme.textSecondary(context)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEligibilityCard() {
    final e = _eligibility;
    if (e == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: e.canClaim
            ? const Color(0xFF51CF66).withOpacity(0.06)
            : AppTheme.warning.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: e.canClaim
              ? const Color(0xFF51CF66).withOpacity(0.2)
              : AppTheme.warning.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Text(e.canClaim ? '✅' : '⚠️', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.eligibilityLabel,
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary(context))),
                const SizedBox(height: 4),
                Text('${e.breadcrumbsInCell} breadcrumbs · ${e.uniqueDays} unique days in this cell',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PRECISION', style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.bold,
          letterSpacing: 2, color: AppTheme.textSecondary(context),
        )),
        const SizedBox(height: 8),
        Row(
          children: [
            _resButton(7, 'Neighborhood', '5.16 km²'),
            const SizedBox(width: 8),
            _resButton(9, 'Building', '105K m²'),
            const SizedBox(width: 8),
            _resButton(10, 'Street', '15K m²'),
          ],
        ),
      ],
    );
  }

  Widget _resButton(int res, String label, String area) {
    final selected = _resolution == res;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _resolution = res);
          _checkEligibility();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00AEEF).withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? const Color(0xFF00AEEF) : AppTheme.border(context),
            ),
          ),
          child: Column(
            children: [
              Text('R$res', style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14,
                color: selected ? const Color(0xFF00AEEF) : AppTheme.textSecondary(context),
              )),
              Text(label, style: TextStyle(fontSize: 10, color: AppTheme.textSecondary(context))),
              Text(area, style: TextStyle(fontSize: 9, color: AppTheme.textMuted(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTierSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CLAIM TYPE', style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.bold,
          letterSpacing: 2, color: AppTheme.textSecondary(context),
        )),
        const SizedBox(height: 8),
        ...ClaimTier.values.map((tier) {
          final eligible = tier == ClaimTier.visitor
              ? (_eligibility?.canVisitor ?? false)
              : tier == ClaimTier.resident
                  ? (_eligibility?.canResident ?? false)
                  : (_eligibility?.canResident ?? false); // sovereign also needs resident level
          final selected = _selectedTier == tier;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: eligible ? () => setState(() => _selectedTier = tier) : null,
              borderRadius: BorderRadius.circular(10),
              child: Opacity(
                opacity: eligible ? 1.0 : 0.4,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF00AEEF).withOpacity(0.08) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? const Color(0xFF00AEEF) : AppTheme.border(context),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(tier.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tier.label, style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selected ? const Color(0xFF00AEEF) : AppTheme.textPrimary(context),
                            )),
                            Text(
                              tier == ClaimTier.visitor
                                  ? 'Post a review or message at this place'
                                  : tier == ClaimTier.resident
                                      ? 'Create a persistent GEPSite page'
                                      : 'Official presence with DNS verification',
                              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context)),
                            ),
                          ],
                        ),
                      ),
                      if (!eligible)
                        Text('${tier.minBreadcrumbs}+ crumbs', style: TextStyle(
                          fontSize: 10, color: AppTheme.textMuted(context))),
                      if (selected)
                        const Icon(Icons.check_circle, color: Color(0xFF00AEEF), size: 20),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildContentEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONTENT', style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.bold,
          letterSpacing: 2, color: AppTheme.textSecondary(context),
        )),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: _selectedTier == ClaimTier.visitor ? 'Review Title' : 'GEPSite Name',
            hintText: _selectedTier == ClaimTier.visitor
                ? 'Great coffee shop!'
                : 'My Business Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          maxLength: 100,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descController,
          decoration: InputDecoration(
            labelText: 'Description',
            hintText: _selectedTier == ClaimTier.visitor
                ? 'What did you think of this place?'
                : 'What is this place? Hours, contact, info...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          maxLines: 4,
          maxLength: 500,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'Website URL (optional)',
            hintText: 'https://...',
            prefixIcon: const Icon(Icons.link),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          keyboardType: TextInputType.url,
        ),
      ],
    );
  }

  Widget _buildDomainField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('DNS BRIDGE (optional)', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold,
            letterSpacing: 2, color: AppTheme.textSecondary(context),
          )),
          const SizedBox(height: 8),
          TextField(
            controller: _domainController,
            decoration: InputDecoration(
              labelText: 'Your domain',
              hintText: 'example.com',
              prefixIcon: const Icon(Icons.dns),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              helperText: 'Add _gep TXT record to verify ownership',
              helperMaxLines: 2,
            ),
            keyboardType: TextInputType.url,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Text('🌍', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            _result!.isVisitor ? 'Review Posted!' : 'GEPSite Created!',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _result!.title,
            style: const TextStyle(fontSize: 18, color: Color(0xFF00AEEF)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // GEA display
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF00AEEF).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                const Text('GEOEPOCH ADDRESS', style: TextStyle(
                  fontSize: 9, letterSpacing: 2, color: Color(0xFF636E72))),
                const SizedBox(height: 6),
                Text(_result!.gea, style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace', color: Color(0xFF00AEEF)),
                  textAlign: TextAlign.center),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _successStat(_result!.claimTier.toUpperCase(), 'Tier'),
              _successStat('R${_result!.resolution}', 'Resolution'),
              _successStat('${_result!.breadcrumbsInCell}', 'Crumbs'),
            ],
          ),
          const SizedBox(height: 24),

          // View on Physical Web
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openPhysicalWeb,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('VIEW ON PHYSICAL WEB'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00AEEF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Share GEA
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _result!.gea));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('GEA copied to clipboard')),
                );
              },
              icon: const Icon(Icons.share),
              label: const Text('COPY GEA ADDRESS'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00AEEF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Done
          TextButton(
            onPressed: () => Navigator.pop(context, _result),
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  Widget _successStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF00AEEF))),
        Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context))),
      ],
    );
  }
}

// Extension for double formatting in Dart
extension _DoubleExt on double {
  String toFixed(int decimals) => toStringAsFixed(decimals);
}
