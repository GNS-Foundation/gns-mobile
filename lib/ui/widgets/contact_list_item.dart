/// Contact List Item Widget
/// 
/// Displays a contact entry in a list.
/// 
/// Location: lib/ui/widgets/contact_list_item.dart

import 'package:flutter/material.dart';
import '../../core/contacts/contact_entry.dart';
import '../../core/theme/theme_service.dart';

class ContactListItem extends StatelessWidget {
  final ContactEntry contact;
  final VoidCallback? onTap;

  const ContactListItem({super.key, required this.contact, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.2),
          child: contact.avatarUrl != null
              ? ClipOval(
                  child: Image.network(
                    contact.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Text(
                      contact.displayTitle[0].toUpperCase(),
                      style: const TextStyle(color: AppTheme.primary),
                    ),
                  ),
                )
              : Text(
                  contact.displayTitle[0].toUpperCase(),
                  style: const TextStyle(color: AppTheme.primary),
                ),
        ),
        title: Text(contact.displayTitle),
        subtitle: Text(
          contact.subtitle,
          style: TextStyle(color: AppTheme.textMuted(context)),
        ),
        trailing: Text(
          contact.trustLabel,
          style: const TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
