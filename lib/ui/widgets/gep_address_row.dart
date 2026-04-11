/// GEP Address Row Widget
///
/// Compact widget that displays a user's GeoEpoch Address (GEA)
/// alongside their @handle in the identity card.
///
/// Shows: GEP icon + resolution label + short GEA + copy button
/// Tap opens gep.gcrumbs.com with the coordinates pre-loaded.
///
/// Location: lib/ui/widgets/gep_address_row.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/gep/gep_address.dart';
import '../../core/theme/theme_service.dart';

class GepAddressRow extends StatelessWidget {
  final GepAddress gea;
  final bool compact;

  const GepAddressRow({
    super.key,
    required this.gea,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openVisualizer(),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF00AEEF).withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF00AEEF).withOpacity(0.15),
          ),
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // GEP icon
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF00AEEF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Text('🌍', style: TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 10),

            // GEA info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'GEP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF00AEEF),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00AEEF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'R${gea.resolution}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF00AEEF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        gea.resolutionLabel,
                        style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    gea.shortDisplay,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AppTheme.textSecondary(context),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Copy button
            IconButton(
              icon: Icon(
                Icons.copy_rounded,
                size: 16,
                color: AppTheme.textSecondary(context),
              ),
              onPressed: () => _copyGea(context),
              tooltip: 'Copy GEA',
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  void _copyGea(BuildContext context) {
    Clipboard.setData(ClipboardData(text: gea.encoded));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('GEP address copied: ${gea.shortDisplay}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openVisualizer() async {
    if (gea.lat != null && gea.lon != null) {
      // Open the GEP visualizer with this location pre-set
      final url = Uri.parse('https://gep.gcrumbs.com');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }
  }
}

/// Compact inline GEA chip — for use in lists, message headers, etc.
class GepAddressChip extends StatelessWidget {
  final GepAddress gea;

  const GepAddressChip({super.key, required this.gea});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF00AEEF).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00AEEF).withOpacity(0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🌍', style: TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            gea.tinyDisplay,
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: Color(0xFF00AEEF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
