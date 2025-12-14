/// Identity Card Widget
/// 
/// Displays identity information with avatar, handle, stats, and chain status.
/// 
/// Location: lib/ui/widgets/identity_card.dart

import 'package:flutter/material.dart';
import '../../core/profile/identity_view_data.dart';
import '../../core/theme/theme_service.dart';

class IdentityCard extends StatelessWidget {
  final IdentityViewData identity;
  final VoidCallback? onEdit;

  const IdentityCard({super.key, required this.identity, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: identity.avatarUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            identity.avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => 
                                const Center(child: Text('🔐', style: TextStyle(fontSize: 28))),
                          ),
                        )
                      : const Center(child: Text('🔐', style: TextStyle(fontSize: 28))),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        identity.displayLabel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        identity.displayTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (identity.isOwnIdentity && onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: onEdit,
                  ),
              ],
            ),
            if (identity.bio != null) ...[
              const SizedBox(height: 12),
              Text(
                identity.bio!,
                style: TextStyle(color: AppTheme.textSecondary(context)),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  label: 'Crumbs',
                  value: identity.breadcrumbLabel,
                  icon: '🍞',
                ),
                _StatItem(
                  label: 'Trust',
                  value: identity.trustLabel,
                  icon: identity.trustLevel.emoji,
                ),
                _StatItem(
                  label: 'Active',
                  value: identity.daysLabel,
                  icon: '📅',
                ),
              ],
            ),
            if (identity.isOwnIdentity) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    identity.chainValid ? Icons.check_circle : Icons.warning,
                    size: 14,
                    color: identity.chainValid ? AppTheme.secondary : AppTheme.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    identity.chainValid ? 'Chain verified' : 'Chain issues',
                    style: TextStyle(
                      fontSize: 12,
                      color: identity.chainValid ? AppTheme.secondary : AppTheme.warning,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String icon;

  const _StatItem({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
        ),
      ],
    );
  }
}
