// ============================================================
// GNS gSITE SERVICE
// ============================================================
// Location: lib/core/gsite/gsite_service.dart
// Purpose: API client for gSite CRUD operations
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'gsite_models.dart';

// ============================================================
// VALIDATION RESULT
// ============================================================

class ValidationResult {
  final bool valid;
  final List<ValidationError> errors;
  final List<ValidationWarning> warnings;

  ValidationResult({
    required this.valid,
    this.errors = const [],
    this.warnings = const [],
  });

  factory ValidationResult.fromJson(Map<String, dynamic> json) => ValidationResult(
    valid: json['valid'] as bool,
    errors: (json['errors'] as List<dynamic>?)
        ?.map((e) => ValidationError.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    warnings: (json['warnings'] as List<dynamic>?)
        ?.map((w) => ValidationWarning.fromJson(w as Map<String, dynamic>))
        .toList() ?? [],
  );
}

class ValidationError {
  final String path;
  final String message;
  final String? keyword;

  ValidationError({required this.path, required this.message, this.keyword});

  factory ValidationError.fromJson(Map<String, dynamic> json) => ValidationError(
    path: json['path'] as String? ?? '',
    message: json['message'] as String,
    keyword: json['keyword'] as String?,
  );
}

class ValidationWarning {
  final String path;
  final String message;

  ValidationWarning({required this.path, required this.message});

  factory ValidationWarning.fromJson(Map<String, dynamic> json) => ValidationWarning(
    path: json['path'] as String,
    message: json['message'] as String,
  );
}

// ============================================================
// gSITE SERVICE RESULT
// ============================================================

class GSiteResult<T> {
  final bool success;
  final T? data;
  final String? error;
  final List<ValidationWarning> warnings;

  GSiteResult({
    required this.success,
    this.data,
    this.error,
    this.warnings = const [],
  });

  factory GSiteResult.success(T data, {List<ValidationWarning>? warnings}) => GSiteResult(
    success: true,
    data: data,
    warnings: warnings ?? [],
  );

  factory GSiteResult.failure(String error) => GSiteResult(
    success: false,
    error: error,
  );
}

// ============================================================
// gSITE SERVICE
// ============================================================

class GSiteService {
  static const String _defaultBaseUrl = 'https://gns-browser-production.up.railway.app';
  
  final String baseUrl;
  final http.Client _client;

  GSiteService({
    String? baseUrl,
    http.Client? client,
  }) : baseUrl = baseUrl ?? _defaultBaseUrl,
       _client = client ?? http.Client();

  // ----------------------------------------------------------
  // GET gSITE
  // ----------------------------------------------------------

  /// Fetch a gSite by identifier
  /// [identifier] - @handle or namespace@
  /// [version] - Optional specific version (default: latest)
  Future<GSiteResult<GSite>> getGSite(String identifier, {int? version}) async {
    try {
      final uri = Uri.parse('$baseUrl/gsite/$identifier')
          .replace(queryParameters: version != null ? {'version': version.toString()} : null);

      print('🌐 GET gSite: $uri');

      final response = await _client.get(uri, headers: {
        'Content-Type': 'application/json',
      });

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && json['success'] == true) {
        final gsite = GSite.fromJson(json['data'] as Map<String, dynamic>);
        return GSiteResult.success(gsite);
      } else {
        return GSiteResult.failure(json['error'] as String? ?? 'Failed to fetch gSite');
      }
    } catch (e) {
      print('❌ Error fetching gSite: $e');
      return GSiteResult.failure(e.toString());
    }
  }

  // ----------------------------------------------------------
  // VALIDATE gSITE
  // ----------------------------------------------------------

  /// Validate a gSite without saving
  /// Returns validation result with errors and warnings
  Future<ValidationResult> validateGSite(GSite gsite) async {
    return validateGSiteJson(gsite.toJson());
  }

  /// Validate gSite JSON without saving
  Future<ValidationResult> validateGSiteJson(Map<String, dynamic> gsiteJson) async {
    try {
      final identifier = gsiteJson['@id'] as String? ?? '@temp';
      final uri = Uri.parse('$baseUrl/gsite/$identifier/validate');

      print('✅ Validating gSite: $uri');

      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(gsiteJson),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return ValidationResult.fromJson(json);
      } else {
        return ValidationResult(
          valid: false,
          errors: [ValidationError(path: '', message: json['error'] as String? ?? 'Validation failed')],
        );
      }
    } catch (e) {
      print('❌ Error validating gSite: $e');
      return ValidationResult(
        valid: false,
        errors: [ValidationError(path: '', message: e.toString())],
      );
    }
  }

  // ----------------------------------------------------------
  // SAVE gSITE
  // ----------------------------------------------------------

  /// Save/update a gSite (requires authentication)
  /// [gsite] - The gSite to save
  /// [privateKey] - Ed25519 private key for signing the request
  /// [publicKey] - Ed25519 public key (hex)
  Future<GSiteResult<GSite>> saveGSite(
    GSite gsite, {
    required List<int> privateKey,
    required String publicKey,
  }) async {
    return saveGSiteJson(
      gsite.toJson(),
      gsite.id,
      privateKey: privateKey,
      publicKey: publicKey,
    );
  }

  /// Save/update gSite from JSON
  Future<GSiteResult<GSite>> saveGSiteJson(
    Map<String, dynamic> gsiteJson,
    String identifier, {
    required List<int> privateKey,
    required String publicKey,
  }) async {
    try {
      // First validate
      final validation = await validateGSiteJson(gsiteJson);
      if (!validation.valid) {
        return GSiteResult.failure(
          'Validation failed: ${validation.errors.map((e) => e.message).join(', ')}',
        );
      }

      // Generate auth headers
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final message = 'PUT:/gsite/$identifier:$timestamp';
      final signature = await _signMessage(message, privateKey);

      final uri = Uri.parse('$baseUrl/gsite/$identifier');

      print('📝 PUT gSite: $uri');

      final response = await _client.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-PublicKey': publicKey,
          'X-GNS-Signature': signature,
          'X-GNS-Timestamp': timestamp,
        },
        body: jsonEncode(gsiteJson),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && json['success'] == true) {
        final gsite = GSite.fromJson(json['data'] as Map<String, dynamic>);
        final warnings = (json['warnings'] as List<dynamic>?)
            ?.map((w) => ValidationWarning.fromJson(w as Map<String, dynamic>))
            .toList();
        return GSiteResult.success(gsite, warnings: warnings);
      } else {
        return GSiteResult.failure(json['error'] as String? ?? 'Failed to save gSite');
      }
    } catch (e) {
      print('❌ Error saving gSite: $e');
      return GSiteResult.failure(e.toString());
    }
  }

  // ----------------------------------------------------------
  // GET VERSION HISTORY
  // ----------------------------------------------------------

  /// Get version history for a gSite
  Future<GSiteResult<List<GSiteVersion>>> getHistory(
    String identifier, {
    int limit = 10,
    int offset = 0,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/gsite/$identifier/history').replace(
        queryParameters: {
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
      );

      print('📜 GET gSite history: $uri');

      final response = await _client.get(uri, headers: {
        'Content-Type': 'application/json',
      });

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && json['success'] == true) {
        final versions = (json['versions'] as List<dynamic>)
            .map((v) => GSiteVersion.fromJson(v as Map<String, dynamic>))
            .toList();
        return GSiteResult.success(versions);
      } else {
        return GSiteResult.failure(json['error'] as String? ?? 'Failed to fetch history');
      }
    } catch (e) {
      print('❌ Error fetching history: $e');
      return GSiteResult.failure(e.toString());
    }
  }

  // ----------------------------------------------------------
  // VALIDATE THEME
  // ----------------------------------------------------------

  /// Validate a PANTHERA theme
  Future<ValidationResult> validateTheme(Map<String, dynamic> themeJson) async {
    try {
      final uri = Uri.parse('$baseUrl/gsite/theme/validate');

      print('🎨 Validating theme');

      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(themeJson),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return ValidationResult.fromJson(json);
      } else {
        return ValidationResult(
          valid: false,
          errors: [ValidationError(path: '', message: json['error'] as String? ?? 'Validation failed')],
        );
      }
    } catch (e) {
      print('❌ Error validating theme: $e');
      return ValidationResult(
        valid: false,
        errors: [ValidationError(path: '', message: e.toString())],
      );
    }
  }

  // ----------------------------------------------------------
  // HELPERS
  // ----------------------------------------------------------

  /// Sign a message with Ed25519 private key
  Future<String> _signMessage(String message, List<int> privateKey) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(privateKey);
    final signature = await algorithm.sign(
      utf8.encode(message),
      keyPair: keyPair,
    );
    return base64Encode(signature.bytes);
  }

  /// Dispose the HTTP client
  void dispose() {
    _client.close();
  }
}

// ============================================================
// VERSION INFO
// ============================================================

class GSiteVersion {
  final int version;
  final DateTime updated;

  GSiteVersion({required this.version, required this.updated});

  factory GSiteVersion.fromJson(Map<String, dynamic> json) => GSiteVersion(
    version: json['version'] as int,
    updated: DateTime.parse(json['updated'] as String),
  );
}

// ============================================================
// SINGLETON INSTANCE
// ============================================================

GSiteService? _instance;

GSiteService get gsiteService {
  _instance ??= GSiteService();
  return _instance!;
}
