/// Contact Storage - Phase 3A (Updated with encryption_key)
/// 
/// SQLite storage for contacts and search history.
/// 
/// Location: lib/core/contacts/contact_storage.dart

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'contact_entry.dart';

class ContactStorage {
  static final ContactStorage _instance = ContactStorage._internal();
  factory ContactStorage() => _instance;
  ContactStorage._internal();

  Database? _database;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDir.path, 'gns_contacts.db');

    _database = await openDatabase(
      dbPath,
      version: 2,  // ✅ CHANGED: Bumped from 1 to 2
      onCreate: _createTables,
      onUpgrade: _onUpgrade,  // ✅ ADDED: Migration handler
    );

    _initialized = true;
    debugPrint('Contact storage initialized: $dbPath');
  }

  Future<void> _createTables(Database db, int version) async {
    // Contacts table
    await db.execute('''
      CREATE TABLE contacts (
        id TEXT PRIMARY KEY,
        public_key TEXT NOT NULL UNIQUE,
        encryption_key TEXT,
        handle TEXT,
        display_name TEXT,
        avatar_url TEXT,
        trust_score REAL,
        nickname TEXT,
        notes TEXT,
        added_at TEXT NOT NULL,
        last_synced TEXT,
        is_favorite INTEGER DEFAULT 0
      )
    ''');

    // Search history table
    await db.execute('''
      CREATE TABLE search_history (
        id TEXT PRIMARY KEY,
        query TEXT NOT NULL,
        result_public_key TEXT,
        result_handle TEXT,
        searched_at TEXT NOT NULL
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_contacts_handle ON contacts(handle)');
    await db.execute('CREATE INDEX idx_contacts_favorite ON contacts(is_favorite)');
    await db.execute('CREATE INDEX idx_contacts_added ON contacts(added_at)');
    await db.execute('CREATE INDEX idx_search_history_time ON search_history(searched_at)');

    debugPrint('Contact tables created with encryption_key column');
  }

  // ✅ ADDED: Migration method for existing databases
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('📦 Upgrading contact database from v$oldVersion to v$newVersion');
    
    if (oldVersion < 2) {
      // Add encryption_key column for existing databases
      await db.execute('ALTER TABLE contacts ADD COLUMN encryption_key TEXT');
      debugPrint('✅ Added encryption_key column to contacts table');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  // ==================== CONTACTS ====================

  /// Add a new contact
  Future<int> addContact(ContactEntry contact) async {
    await _ensureInitialized();

    final result = await _database!.insert(
      'contacts',
      contact.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('Contact added: ${contact.displayTitle}');
    return result;
  }

  /// Update existing contact
  Future<void> updateContact(ContactEntry contact) async {
    await _ensureInitialized();

    await _database!.update(
      'contacts',
      contact.toMap(),
      where: 'public_key = ?',
      whereArgs: [contact.publicKey],
    );

    debugPrint('Contact updated: ${contact.displayTitle}');
  }

  /// Delete contact by public key
  Future<void> deleteContact(String publicKey) async {
    await _ensureInitialized();

    await _database!.delete(
      'contacts',
      where: 'public_key = ?',
      whereArgs: [publicKey],
    );

    debugPrint('Contact deleted: ${publicKey.substring(0, 8)}...');
  }

  /// Remove contact (alias for deleteContact)
  Future<void> removeContact(String publicKey) async {
    await deleteContact(publicKey);
  }

  /// Get contact by public key
  Future<ContactEntry?> getContact(String publicKey) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'contacts',
      where: 'public_key = ?',
      whereArgs: [publicKey],
    );

    if (results.isEmpty) return null;
    return ContactEntry.fromMap(results.first);
  }

  /// Get contact by handle
  Future<ContactEntry?> getContactByHandle(String handle) async {
    await _ensureInitialized();

    final cleanHandle = handle.replaceAll('@', '').toLowerCase();
    final results = await _database!.query(
      'contacts',
      where: 'LOWER(handle) = ?',
      whereArgs: [cleanHandle],
    );

    if (results.isEmpty) return null;
    return ContactEntry.fromMap(results.first);
  }

  /// Check if contact exists
  Future<bool> hasContact(String publicKey) async {
    final contact = await getContact(publicKey);
    return contact != null;
  }

  /// Check if public key is a contact (alias for hasContact)
  Future<bool> isContact(String publicKey) async {
    return await hasContact(publicKey);
  }

  /// Get all contacts, sorted by display title
  Future<List<ContactEntry>> getAllContacts() async {
    await _ensureInitialized();

    final results = await _database!.query(
      'contacts',
      orderBy: 'COALESCE(nickname, handle, public_key) ASC',
    );

    return results.map((m) => ContactEntry.fromMap(m)).toList();
  }

  /// Get favorite contacts
  Future<List<ContactEntry>> getFavorites() async {
    await _ensureInitialized();

    final results = await _database!.query(
      'contacts',
      where: 'is_favorite = 1',
      orderBy: 'COALESCE(nickname, handle, public_key) ASC',
    );

    return results.map((m) => ContactEntry.fromMap(m)).toList();
  }

  /// Get recent contacts (by added_at)
  Future<List<ContactEntry>> getRecentContacts({int limit = 10}) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'contacts',
      orderBy: 'added_at DESC',
      limit: limit,
    );

    return results.map((m) => ContactEntry.fromMap(m)).toList();
  }

  /// Search contacts by query
  Future<List<ContactEntry>> searchContacts(String query) async {
    await _ensureInitialized();

    final searchTerm = '%${query.toLowerCase()}%';
    final results = await _database!.query(
      'contacts',
      where: 'LOWER(handle) LIKE ? OR LOWER(display_name) LIKE ? OR LOWER(nickname) LIKE ? OR public_key LIKE ?',
      whereArgs: [searchTerm, searchTerm, searchTerm, searchTerm],
      orderBy: 'COALESCE(nickname, handle, public_key) ASC',
    );

    return results.map((m) => ContactEntry.fromMap(m)).toList();
  }

  /// Toggle favorite status
  Future<void> toggleFavorite(String publicKey) async {
    await _ensureInitialized();

    final contact = await getContact(publicKey);
    if (contact == null) return;

    await _database!.update(
      'contacts',
      {'is_favorite': contact.isFavorite ? 0 : 1},
      where: 'public_key = ?',
      whereArgs: [publicKey],
    );

    debugPrint('Contact favorite toggled: ${contact.displayTitle}');
  }

  /// Get contact count
  Future<int> getContactCount() async {
    await _ensureInitialized();
    final result = await _database!.rawQuery('SELECT COUNT(*) as count FROM contacts');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== SEARCH HISTORY ====================

  /// Add search to history
  Future<void> addSearchHistory(SearchHistoryEntry entry) async {
    await _ensureInitialized();

    await _database!.insert(
      'search_history',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get recent searches
  Future<List<SearchHistoryEntry>> getRecentSearches({int limit = 10}) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'search_history',
      orderBy: 'searched_at DESC',
      limit: limit,
    );

    return results.map((m) => SearchHistoryEntry.fromMap(m)).toList();
  }

  /// Clear search history
  Future<void> clearSearchHistory() async {
    await _ensureInitialized();
    await _database!.delete('search_history');
    debugPrint('Search history cleared');
  }

  /// Delete old search history (older than days)
  Future<void> pruneSearchHistory({int olderThanDays = 30}) async {
    await _ensureInitialized();

    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    await _database!.delete(
      'search_history',
      where: 'searched_at < ?',
      whereArgs: [cutoff.toIso8601String()],
    );
  }

  // ==================== UTILITY ====================

  /// Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initialized = false;
  }

  /// Delete all data
  Future<void> deleteAll() async {
    await _ensureInitialized();
    await _database!.delete('contacts');
    await _database!.delete('search_history');
    debugPrint('All contact data deleted');
  }

  /// Export contacts as JSON
  Future<List<Map<String, dynamic>>> exportContacts() async {
    await _ensureInitialized();
    final contacts = await getAllContacts();
    return contacts.map((c) => c.toMap()).toList();
  }

  /// Import contacts from JSON
  Future<int> importContacts(List<Map<String, dynamic>> data) async {
    await _ensureInitialized();
    
    int imported = 0;
    for (final map in data) {
      try {
        final contact = ContactEntry.fromMap(map);
        await addContact(contact);
        imported++;
      } catch (e) {
        debugPrint('Failed to import contact: $e');
      }
    }
    
    debugPrint('Imported $imported contacts');
    return imported;
  }
}
