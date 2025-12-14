/// Transaction Storage - Encrypted Local Database
/// 
/// Stores payment transactions locally with encryption at rest.
/// Mirrors the pattern from message_storage.dart.
/// 
/// Location: lib/core/financial/transaction_storage.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:cryptography/cryptography.dart';
import 'payment_payload.dart';

/// Transaction status enum
enum TransactionStatus {
  pending,    // Payment initiated, waiting for response
  accepted,   // Recipient accepted
  rejected,   // Recipient rejected
  settled,    // Payment confirmed on rail
  failed,     // Payment failed
  expired,    // Payment expired before completion
}

/// Transaction direction
enum TransactionDirection {
  outgoing,   // We sent the payment
  incoming,   // We received the payment
}

/// Local transaction representation
class GnsTransaction {
  final String id;
  final String fromPublicKey;
  final String? fromHandle;
  final String toPublicKey;
  final String? toHandle;
  final String amount;
  final String currency;
  final String? memo;
  final String routeType;
  final TransactionStatus status;
  final TransactionDirection direction;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? acknowledgedAt;
  final DateTime? settledAt;
  final String? failureReason;
  final String? externalReference;
  final String? envelopeId;
  final Map<String, dynamic> metadata;

  GnsTransaction({
    required this.id,
    required this.fromPublicKey,
    this.fromHandle,
    required this.toPublicKey,
    this.toHandle,
    required this.amount,
    required this.currency,
    this.memo,
    required this.routeType,
    required this.status,
    required this.direction,
    required this.createdAt,
    required this.updatedAt,
    this.acknowledgedAt,
    this.settledAt,
    this.failureReason,
    this.externalReference,
    this.envelopeId,
    this.metadata = const {},
  });

  double get amountDouble => double.parse(amount);
  bool get isOutgoing => direction == TransactionDirection.outgoing;
  bool get isIncoming => direction == TransactionDirection.incoming;
  String get counterpartyKey => isOutgoing ? toPublicKey : fromPublicKey;
  String? get counterpartyHandle => isOutgoing ? toHandle : fromHandle;

  String get counterpartyDisplay {
    final handle = counterpartyHandle;
    if (handle != null) return '@$handle';
    return 'gns_${counterpartyKey.substring(0, 8)}...';
  }

  String get statusDisplay {
    switch (status) {
      case TransactionStatus.pending: return 'Pending';
      case TransactionStatus.accepted: return 'Accepted';
      case TransactionStatus.rejected: return 'Rejected';
      case TransactionStatus.settled: return 'Completed';
      case TransactionStatus.failed: return 'Failed';
      case TransactionStatus.expired: return 'Expired';
    }
  }

  String get amountFormatted {
    final prefix = isOutgoing ? '-' : '+';
    return '$prefix$amount $currency';
  }

  factory GnsTransaction.fromPayload(
    PaymentTransferPayload payload, {
    required bool isOutgoing,
    String? fromHandle,
    String? toHandle,
    String? envelopeId,
  }) {
    final now = DateTime.now();
    return GnsTransaction(
      id: payload.paymentId,
      fromPublicKey: payload.fromPublicKey,
      fromHandle: fromHandle,
      toPublicKey: payload.toPublicKey,
      toHandle: toHandle,
      amount: payload.amount,
      currency: payload.currency,
      memo: payload.memo,
      routeType: payload.route.type,
      status: TransactionStatus.pending,
      direction: isOutgoing 
          ? TransactionDirection.outgoing 
          : TransactionDirection.incoming,
      createdAt: DateTime.fromMillisecondsSinceEpoch(payload.createdAt),
      updatedAt: now,
      envelopeId: envelopeId,
      metadata: {
        'route_endpoint_id': payload.route.endpointId,
        if (payload.clientReference != null) 'client_reference': payload.clientReference,
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'from_public_key': fromPublicKey,
    'from_handle': fromHandle,
    'to_public_key': toPublicKey,
    'to_handle': toHandle,
    'amount': amount,
    'currency': currency,
    'memo': memo,
    'route_type': routeType,
    'status': status.name,
    'direction': direction.name,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'acknowledged_at': acknowledgedAt?.millisecondsSinceEpoch,
    'settled_at': settledAt?.millisecondsSinceEpoch,
    'failure_reason': failureReason,
    'external_reference': externalReference,
    'envelope_id': envelopeId,
    'metadata': metadata,
  };

  factory GnsTransaction.fromJson(Map<String, dynamic> json) {
    return GnsTransaction(
      id: json['id'] as String,
      fromPublicKey: json['from_public_key'] as String,
      fromHandle: json['from_handle'] as String?,
      toPublicKey: json['to_public_key'] as String,
      toHandle: json['to_handle'] as String?,
      amount: json['amount'] as String,
      currency: json['currency'] as String,
      memo: json['memo'] as String?,
      routeType: json['route_type'] as String,
      status: TransactionStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => TransactionStatus.pending,
      ),
      direction: TransactionDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => TransactionDirection.outgoing,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int),
      acknowledgedAt: json['acknowledged_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['acknowledged_at'] as int)
          : null,
      settledAt: json['settled_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['settled_at'] as int)
          : null,
      failureReason: json['failure_reason'] as String?,
      externalReference: json['external_reference'] as String?,
      envelopeId: json['envelope_id'] as String?,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : {},
    );
  }

  GnsTransaction copyWithStatus(
    TransactionStatus newStatus, {
    String? failureReason,
    String? externalReference,
  }) {
    final now = DateTime.now();
    return GnsTransaction(
      id: id,
      fromPublicKey: fromPublicKey,
      fromHandle: fromHandle,
      toPublicKey: toPublicKey,
      toHandle: toHandle,
      amount: amount,
      currency: currency,
      memo: memo,
      routeType: routeType,
      status: newStatus,
      direction: direction,
      createdAt: createdAt,
      updatedAt: now,
      acknowledgedAt: (newStatus == TransactionStatus.accepted || 
                       newStatus == TransactionStatus.rejected)
          ? now
          : acknowledgedAt,
      settledAt: newStatus == TransactionStatus.settled ? now : settledAt,
      failureReason: failureReason ?? this.failureReason,
      externalReference: externalReference ?? this.externalReference,
      envelopeId: envelopeId,
      metadata: metadata,
    );
  }

  @override
  String toString() => 'GnsTransaction($id: $statusDisplay $amountFormatted)';
}

/// Transaction storage service
class TransactionStorage {
  static const _dbName = 'gns_transactions.db';
  static const _dbVersion = 1;
  
  Database? _db;
  SecretKey? _encryptionKey;
  final _cipher = AesGcm.with256bits();
  
  bool get isInitialized => _db != null && _encryptionKey != null;

  Future<void> initialize(Uint8List privateKey) async {
    if (_db != null) return;
    
    _encryptionKey = await _deriveStorageKey(privateKey);
    
    final documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDir.path, _dbName);
    
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        from_public_key TEXT NOT NULL,
        from_handle TEXT,
        to_public_key TEXT NOT NULL,
        to_handle TEXT,
        amount TEXT NOT NULL,
        currency TEXT NOT NULL,
        memo_encrypted TEXT,
        route_type TEXT NOT NULL,
        status TEXT NOT NULL,
        direction TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        acknowledged_at INTEGER,
        settled_at INTEGER,
        failure_reason TEXT,
        external_reference TEXT,
        envelope_id TEXT,
        metadata_encrypted TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_tx_parties ON transactions(from_public_key, to_public_key)');
    await db.execute('CREATE INDEX idx_tx_status ON transactions(status)');
    await db.execute('CREATE INDEX idx_tx_time ON transactions(created_at DESC)');
    await db.execute('CREATE INDEX idx_tx_direction ON transactions(direction)');
    await db.execute('CREATE INDEX idx_tx_currency ON transactions(currency)');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {}

  Future<SecretKey> _deriveStorageKey(Uint8List privateKey) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final inputKey = SecretKeyData(privateKey.sublist(0, 32));
    return await hkdf.deriveKey(
      secretKey: inputKey,
      info: utf8.encode('gns-transaction-storage-v1'),
      nonce: Uint8List(0),
    );
  }

  Future<String> _encrypt(String plaintext) async {
    if (_encryptionKey == null) throw StateError('Storage not initialized');
    final data = utf8.encode(plaintext);
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(data, secretKey: _encryptionKey!, nonce: nonce);
    final combined = Uint8List.fromList([...nonce, ...secretBox.cipherText, ...secretBox.mac.bytes]);
    return base64Encode(combined);
  }

  Future<String> _decrypt(String encrypted) async {
    if (_encryptionKey == null) throw StateError('Storage not initialized');
    final combined = base64Decode(encrypted);
    final nonce = combined.sublist(0, 12);
    final ciphertext = combined.sublist(12, combined.length - 16);
    final mac = Mac(combined.sublist(combined.length - 16));
    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: mac);
    final plaintext = await _cipher.decrypt(secretBox, secretKey: _encryptionKey!);
    return utf8.decode(plaintext);
  }

  Future<void> saveTransaction(GnsTransaction transaction) async {
    final memoEncrypted = transaction.memo != null ? await _encrypt(transaction.memo!) : null;
    final metadataEncrypted = await _encrypt(jsonEncode(transaction.metadata));
    
    await _db!.insert('transactions', {
      'id': transaction.id,
      'from_public_key': transaction.fromPublicKey,
      'from_handle': transaction.fromHandle,
      'to_public_key': transaction.toPublicKey,
      'to_handle': transaction.toHandle,
      'amount': transaction.amount,
      'currency': transaction.currency,
      'memo_encrypted': memoEncrypted,
      'route_type': transaction.routeType,
      'status': transaction.status.name,
      'direction': transaction.direction.name,
      'created_at': transaction.createdAt.millisecondsSinceEpoch,
      'updated_at': transaction.updatedAt.millisecondsSinceEpoch,
      'acknowledged_at': transaction.acknowledgedAt?.millisecondsSinceEpoch,
      'settled_at': transaction.settledAt?.millisecondsSinceEpoch,
      'failure_reason': transaction.failureReason,
      'external_reference': transaction.externalReference,
      'envelope_id': transaction.envelopeId,
      'metadata_encrypted': metadataEncrypted,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<GnsTransaction?> getTransaction(String id) async {
    final rows = await _db!.query('transactions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return await _transactionFromRow(rows.first);
  }

  Future<List<GnsTransaction>> getTransactions({
    TransactionDirection? direction,
    TransactionStatus? status,
    String? currency,
    String? counterpartyKey,
    int limit = 50,
    int offset = 0,
  }) async {
    final conditions = <String>[];
    final args = <dynamic>[];
    
    if (direction != null) { conditions.add('direction = ?'); args.add(direction.name); }
    if (status != null) { conditions.add('status = ?'); args.add(status.name); }
    if (currency != null) { conditions.add('currency = ?'); args.add(currency); }
    if (counterpartyKey != null) {
      conditions.add('(from_public_key = ? OR to_public_key = ?)');
      args.addAll([counterpartyKey, counterpartyKey]);
    }
    
    final rows = await _db!.query('transactions',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit, offset: offset,
    );
    
    final results = <GnsTransaction>[];
    for (final row in rows) { results.add(await _transactionFromRow(row)); }
    return results;
  }

  Future<List<GnsTransaction>> getPendingIncoming() async {
    return getTransactions(direction: TransactionDirection.incoming, status: TransactionStatus.pending);
  }

  Future<List<GnsTransaction>> getPendingOutgoing() async {
    return getTransactions(direction: TransactionDirection.outgoing, status: TransactionStatus.pending);
  }

  Future<void> updateStatus(String id, TransactionStatus status, {String? failureReason, String? externalReference}) async {
    final transaction = await getTransaction(id);
    if (transaction == null) return;
    final updated = transaction.copyWithStatus(status, failureReason: failureReason, externalReference: externalReference);
    await saveTransaction(updated);
  }

  Future<double> getTotalSent({required DateTime since, String? currency}) async {
    final conditions = ['direction = ?', 'created_at >= ?', 'status IN (?, ?, ?)'];
    final args = <dynamic>[
      TransactionDirection.outgoing.name, 
      since.millisecondsSinceEpoch,
      TransactionStatus.pending.name, 
      TransactionStatus.accepted.name, 
      TransactionStatus.settled.name,
    ];
    if (currency != null) { conditions.add('currency = ?'); args.add(currency); }
    
    final rows = await _db!.query('transactions', columns: ['amount'],
      where: conditions.join(' AND '), whereArgs: args);
    
    double total = 0.0;
    for (final row in rows) {
      total += double.parse(row['amount'] as String);
    }
    return total;
  }

  Future<double> getTotalReceived({required DateTime since, String? currency}) async {
    final conditions = ['direction = ?', 'created_at >= ?', 'status IN (?, ?)'];
    final args = <dynamic>[
      TransactionDirection.incoming.name, 
      since.millisecondsSinceEpoch,
      TransactionStatus.accepted.name, 
      TransactionStatus.settled.name,
    ];
    if (currency != null) { conditions.add('currency = ?'); args.add(currency); }
    
    final rows = await _db!.query('transactions', columns: ['amount'],
      where: conditions.join(' AND '), whereArgs: args);
    
    double total = 0.0;
    for (final row in rows) {
      total += double.parse(row['amount'] as String);
    }
    return total;
  }

  Future<void> deleteTransaction(String id) async {
    await _db!.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<GnsTransaction> _transactionFromRow(Map<String, dynamic> row) async {
    String? memo;
    if (row['memo_encrypted'] != null) { memo = await _decrypt(row['memo_encrypted'] as String); }
    
    Map<String, dynamic> metadata = {};
    if (row['metadata_encrypted'] != null) {
      final decrypted = await _decrypt(row['metadata_encrypted'] as String);
      metadata = jsonDecode(decrypted) as Map<String, dynamic>;
    }
    
    return GnsTransaction(
      id: row['id'] as String,
      fromPublicKey: row['from_public_key'] as String,
      fromHandle: row['from_handle'] as String?,
      toPublicKey: row['to_public_key'] as String,
      toHandle: row['to_handle'] as String?,
      amount: row['amount'] as String,
      currency: row['currency'] as String,
      memo: memo,
      routeType: row['route_type'] as String,
      status: TransactionStatus.values.firstWhere((s) => s.name == row['status'], orElse: () => TransactionStatus.pending),
      direction: TransactionDirection.values.firstWhere((d) => d.name == row['direction'], orElse: () => TransactionDirection.outgoing),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      acknowledgedAt: row['acknowledged_at'] != null ? DateTime.fromMillisecondsSinceEpoch(row['acknowledged_at'] as int) : null,
      settledAt: row['settled_at'] != null ? DateTime.fromMillisecondsSinceEpoch(row['settled_at'] as int) : null,
      failureReason: row['failure_reason'] as String?,
      externalReference: row['external_reference'] as String?,
      envelopeId: row['envelope_id'] as String?,
      metadata: metadata,
    );
  }

  Future<void> close() async { await _db?.close(); _db = null; _encryptionKey = null; }
}
