/// Contacts Tab
/// 
/// Displays saved contacts with search functionality.
/// 
/// Location: lib/ui/contacts/contacts_tab.dart

import 'package:flutter/material.dart';
import '../../core/profile/profile_service.dart';
import '../../core/contacts/contact_entry.dart';
import '../../core/theme/theme_service.dart';
import '../widgets/contact_list_item.dart';
import '../profile/identity_viewer_screen.dart';

class ContactsTab extends StatefulWidget {
  final ProfileService profileService;

  const ContactsTab({super.key, required this.profileService});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final _searchController = TextEditingController();
  List<ContactEntry> _contacts = [];
  bool _isLoading = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await widget.profileService.getContacts();
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);

    final result = query.startsWith('@') || !query.contains('_')
        ? await widget.profileService.lookupByHandle(query.replaceAll('@', ''))
        : await widget.profileService.lookupByPublicKey(query);

    setState(() => _isSearching = false);

    if (!mounted) return;

    if (result.success && result.identity != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IdentityViewerScreen(
            identity: result.identity!,
            profileService: widget.profileService,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Identity not found')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search @handle or public key...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _search,
                      ),
              ),
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _contacts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: AppTheme.textMuted(context)),
                            const SizedBox(height: 16),
                            Text(
                              'No contacts yet',
                              style: TextStyle(color: AppTheme.textSecondary(context)),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Search for identities to add them',
                              style: TextStyle(color: AppTheme.textMuted(context), fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadContacts,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _contacts.length,
                          itemBuilder: (context, index) {
                            final contact = _contacts[index];
                            return ContactListItem(
                              contact: contact,
                              onTap: () => _viewContact(contact),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _viewContact(ContactEntry contact) async {
    final result = await widget.profileService.lookupByPublicKey(contact.publicKey);
    
    if (result.success && result.identity != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IdentityViewerScreen(
            identity: result.identity!,
            profileService: widget.profileService,
          ),
        ),
      );
    }
  }
}
