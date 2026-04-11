// ============================================================
// HIVE WORKER SERVICE — GCRUMBS Mobile Relay Worker
//
// The phone acts as an identity-verified relay node in the
// GEIANT Hive swarm. It claims inference jobs, forwards them
// to compute workers, and earns GNS tokens for routing.
//
// Architecture:
//   Phone registers in swarm_nodes with GNS pk + H3 cell
//   Phone polls for pending jobs every 30s (battery-friendly)
//   Phone claims job → forwards to Railway /hive/v1/chat/completions
//   Phone writes result back → GNS credited to its pk
//
// Location: lib/core/hive/hive_worker_service.dart
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ── Constants ─────────────────────────────────────────────────

const String _kHiveBaseUrl = 'https://kaqwkxfaclyqjlfhxrmt.supabase.co';
const String _kHiveAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImthcXdreGZhY2x5cWpsZmh4cm10Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4MzU4NTAsImV4cCI6MjA4ODQxMTg1MH0.'
    'ClyWNGRxQjpKYzIROPZBqTXDsWvJioGe9pQymDOYBTc';
const String _kRailwayUrl = 'https://gns-browser-production.up.railway.app';
const String _kWorkerEnabledKey = 'hive_worker_enabled';
const String _kWorkerEarningsKey = 'hive_worker_earnings';
const int _kPollIntervalSeconds = 30;
const int _kHeartbeatIntervalSeconds = 60;

// ── Models ────────────────────────────────────────────────────

class HiveWorkerStatus {
  final bool enabled;
  final bool running;
  final String? h3Cell;
  final double tokensEarned;
  final int jobsRelayed;
  final String trustTier;
  final DateTime? lastHeartbeat;
  final String? lastError;

  const HiveWorkerStatus({
    required this.enabled,
    required this.running,
    this.h3Cell,
    required this.tokensEarned,
    required this.jobsRelayed,
    required this.trustTier,
    this.lastHeartbeat,
    this.lastError,
  });

  HiveWorkerStatus copyWith({
    bool? enabled,
    bool? running,
    String? h3Cell,
    double? tokensEarned,
    int? jobsRelayed,
    String? trustTier,
    DateTime? lastHeartbeat,
    String? lastError,
  }) =>
      HiveWorkerStatus(
        enabled: enabled ?? this.enabled,
        running: running ?? this.running,
        h3Cell: h3Cell ?? this.h3Cell,
        tokensEarned: tokensEarned ?? this.tokensEarned,
        jobsRelayed: jobsRelayed ?? this.jobsRelayed,
        trustTier: trustTier ?? this.trustTier,
        lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
        lastError: lastError,
      );
}

class _HiveJob {
  final String id;
  final String h3Cell;
  final String modelId;
  final String prompt;
  final int maxTokens;
  final double temperature;
  final double gnsReward;

  const _HiveJob({
    required this.id,
    required this.h3Cell,
    required this.modelId,
    required this.prompt,
    required this.maxTokens,
    required this.temperature,
    required this.gnsReward,
  });

  factory _HiveJob.fromJson(Map<String, dynamic> j) => _HiveJob(
        id: j['id'] as String,
        h3Cell: j['h3_cell'] as String,
        modelId: j['model_id'] as String? ?? 'tinyllama',
        prompt: j['prompt'] as String,
        maxTokens: j['max_tokens'] as int? ?? 200,
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.7,
        gnsReward: (j['gns_reward'] as num?)?.toDouble() ?? 0.01,
      );
}

// ── Service ───────────────────────────────────────────────────

class HiveWorkerService extends ChangeNotifier {
  static final HiveWorkerService _instance = HiveWorkerService._internal();
  factory HiveWorkerService() => _instance;
  HiveWorkerService._internal();

  HiveWorkerStatus _status = const HiveWorkerStatus(
    enabled: false,
    running: false,
    tokensEarned: 0,
    jobsRelayed: 0,
    trustTier: 'seedling',
  );

  HiveWorkerStatus get status => _status;

  // Identity — set from outside before starting
  String? _workerPk;
  String? _handle;
  String? _h3Cell;

  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  bool _busy = false; // prevents concurrent job processing

  final _headers = {
    'apikey': _kHiveAnonKey,
    'Authorization': 'Bearer $_kHiveAnonKey',
    'Content-Type': 'application/json',
  };

  // ── Public API ──────────────────────────────────────────────

  final _storage = const FlutterSecureStorage();

  Future<void> initialize({
    required String workerPk,
    String? handle,
    String? h3Cell,
  }) async {
    _workerPk = workerPk;
    _handle = handle;
    _h3Cell = h3Cell ?? '861e8050fffffff'; // Rome fallback

    final enabledStr = await _storage.read(key: _kWorkerEnabledKey);
    final earningsStr = await _storage.read(key: _kWorkerEarningsKey);
    final enabled = enabledStr == 'true';
    final earnings = double.tryParse(earningsStr ?? '0') ?? 0.0;

    _status = _status.copyWith(
      enabled: enabled,
      h3Cell: _h3Cell,
      tokensEarned: earnings,
    );
    notifyListeners();

    if (enabled) await start();
  }

  Future<void> setEnabled(bool value) async {
    await _storage.write(key: _kWorkerEnabledKey, value: value.toString());
    _status = _status.copyWith(enabled: value);
    notifyListeners();
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> start() async {
    if (_status.running || _workerPk == null) return;

    _status = _status.copyWith(running: true, lastError: null);
    notifyListeners();

    // Register in swarm
    await _registerNode();

    // Start poll loop
    _pollTimer = Timer.periodic(
      const Duration(seconds: _kPollIntervalSeconds),
      (_) => _pollForJob(),
    );

    // Start heartbeat
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _kHeartbeatIntervalSeconds),
      (_) => _sendHeartbeat(),
    );

    // Immediate first poll
    unawaited(_pollForJob());

    debugPrint('[HiveWorker] Started — pk: ${_workerPk!.substring(0, 8)}...');
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pollTimer = null;
    _heartbeatTimer = null;
    _status = _status.copyWith(running: false);
    notifyListeners();
    await _setOffline();
    debugPrint('[HiveWorker] Stopped');
  }

  // ── Registration ────────────────────────────────────────────

  Future<void> _registerNode() async {
    if (_workerPk == null) return;
    try {
      final hardware = await _detectHardwareAsync();
      final body = jsonEncode({
        'pk': _workerPk,
        'h3_cell': _h3Cell,
        'handle': _handle,
        'hardware': hardware,
        'geo': {'h3Cell': _h3Cell, 'city': 'Mobile', 'country': 'Unknown'},
        'status': 'idle',
        'last_heartbeat': DateTime.now().toIso8601String(),
        'tokens_earned': _status.tokensEarned,
        'worker_version': '0.1.0-mobile',
        'models': <String>[], // relay worker — no local models
        'trust_tier': 'seedling',
      });

      final resp = await http.post(
        Uri.parse('$_kHiveBaseUrl/rest/v1/swarm_nodes?on_conflict=pk'),
        headers: {..._headers, 'Prefer': 'resolution=merge-duplicates'},
        body: body,
      );

      if (resp.statusCode == 200 ||
          resp.statusCode == 201 ||
          resp.statusCode == 204) {
        debugPrint('[HiveWorker] Registered in swarm');
        _status = _status.copyWith(lastError: null);
      } else {
        debugPrint('[HiveWorker] Registration: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      debugPrint('[HiveWorker] Registration error: $e');
      _status = _status.copyWith(lastError: 'Registration failed');
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _detectHardwareAsync() async {
    String platform = 'unknown';
    String cpuModel = 'Mobile CPU';
    double estimatedTflops = 0.5;
    int ramGb = 4;

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        platform = 'ios';
        cpuModel = ios.utsname.machine; // e.g. iPhone15,2
        // Estimate TFLOPS from chip generation
        final model = ios.utsname.machine.toLowerCase();
        if (model.contains('iphone1')) estimatedTflops = 1.8;
        else if (model.contains('iphone1')) estimatedTflops = 1.4;
        else estimatedTflops = 1.0;
        ramGb = 6;
      } else if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        platform = 'android';
        cpuModel = android.hardware;
        estimatedTflops = 0.8;
        ramGb = 4;
      }
    } catch (_) {
      platform = Platform.isIOS ? 'ios' : 'android';
    }

    return {
      'platform': platform,
      'cpuModel': cpuModel,
      'gpuModel': 'Mobile GPU',
      'ramGb': ramGb,
      'estimatedTflops': estimatedTflops,
      'hiveClass': 'relay',
    };
  }

  Map<String, dynamic> _detectHardware() {
    return {
      'platform': Platform.isIOS ? 'ios' : 'android',
      'cpuModel': 'Mobile CPU',
      'gpuModel': 'Mobile GPU',
      'ramGb': 4,
      'estimatedTflops': 0.8,
      'hiveClass': 'relay',
    };
  }

  // ── Heartbeat ───────────────────────────────────────────────

  Future<void> _sendHeartbeat() async {
    if (_workerPk == null) return;
    try {
      await http.patch(
        Uri.parse(
          '$_kHiveBaseUrl/rest/v1/swarm_nodes?pk=eq.$_workerPk',
        ),
        headers: {..._headers, 'Prefer': 'return=minimal'},
        body: jsonEncode({
          'status': _busy ? 'computing' : 'idle',
          'last_heartbeat': DateTime.now().toIso8601String(),
          'tokens_earned': _status.tokensEarned,
        }),
      );
      _status = _status.copyWith(lastHeartbeat: DateTime.now());
      notifyListeners();
    } catch (e) {
      debugPrint('[HiveWorker] Heartbeat error: $e');
    }
  }

  Future<void> _setOffline() async {
    if (_workerPk == null) return;
    try {
      await http.patch(
        Uri.parse('$_kHiveBaseUrl/rest/v1/swarm_nodes?pk=eq.$_workerPk'),
        headers: {..._headers, 'Prefer': 'return=minimal'},
        body: jsonEncode({
          'status': 'offline',
          'last_heartbeat': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  // ── Job polling ─────────────────────────────────────────────

  Future<void> _pollForJob() async {
    if (_busy || _workerPk == null || _h3Cell == null) return;

    try {
      // Claim a job atomically via Postgres RPC
      final resp = await http.post(
        Uri.parse('$_kHiveBaseUrl/rest/v1/rpc/claim_hive_job'),
        headers: _headers,
        body: jsonEncode({
          'p_worker_pk': _workerPk,
          'p_h3_cell': _h3Cell,
          'p_model_id': null, // accept any model
        }),
      );

      if (!resp.statusCode.toString().startsWith('2')) return;
      final rows = jsonDecode(resp.body) as List;
      if (rows.isEmpty) return;

      final job = _HiveJob.fromJson(rows[0] as Map<String, dynamic>);
      _busy = true;
      debugPrint('[HiveWorker] Claimed job ${job.id.substring(0, 8)}');

      await _processJob(job);
    } catch (e) {
      debugPrint('[HiveWorker] Poll error: $e');
    } finally {
      _busy = false;
    }
  }

  // ── Job execution (relay mode) ───────────────────────────────

  Future<void> _processJob(_HiveJob job) async {
    try {
      // Mark computing
      await _patchJob(job.id, {'status': 'computing'});

      // Forward to Railway orchestrator for actual inference
      // The phone relays the job — compute happens on a desktop worker
      final relayResp = await http.post(
        Uri.parse('$_kRailwayUrl/hive/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'X-GNS-PublicKey': _workerPk!,
          'x-hive-h3-cell': job.h3Cell,
        },
        body: jsonEncode({
          'model': job.modelId,
          'messages': [
            {'role': 'user', 'content': job.prompt}
          ],
          'max_tokens': job.maxTokens,
          'temperature': job.temperature,
          'stream': false,
        }),
      ).timeout(const Duration(seconds: 90));

      if (relayResp.statusCode == 200) {
        final data = jsonDecode(relayResp.body) as Map<String, dynamic>;
        final content =
            (data['choices'] as List?)?.firstOrNull?['message']?['content']
                as String? ??
            '';
        final tokensGenerated =
            (data['usage']?['completion_tokens'] as int?) ?? 0;
        final tps = (data['hive']?['tokens_per_second'] as num?)?.toDouble();

        // Post result back to Supabase
        await _patchJob(job.id, {
          'status': 'completed',
          'result_text': content,
          'tokens_generated': tokensGenerated,
          'tokens_per_second': tps,
          'completed_at': DateTime.now().toIso8601String(),
          'error_message': null,
        });

        // Credit routing fee (20% of reward)
        final routingFee = job.gnsReward * 0.20;
        final newEarnings = _status.tokensEarned + routingFee;
        final newJobs = _status.jobsRelayed + 1;

        await _storage.write(
          key: _kWorkerEarningsKey,
          value: newEarnings.toString(),
        );

        _status = _status.copyWith(
          tokensEarned: newEarnings,
          jobsRelayed: newJobs,
          lastHeartbeat: DateTime.now(),
        );
        notifyListeners();

        debugPrint(
          '[HiveWorker] Job ${job.id.substring(0, 8)} relayed — '
          '+${routingFee.toStringAsFixed(4)} GNS',
        );
      } else {
        await _patchJob(job.id, {
          'status': 'failed',
          'error_message': 'Relay failed: ${relayResp.statusCode}',
          'completed_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('[HiveWorker] Job error: $e');
      try {
        await _patchJob(job.id, {
          'status': 'failed',
          'error_message': e.toString(),
          'completed_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }
  }

  Future<void> _patchJob(String jobId, Map<String, dynamic> fields) async {
    await http.patch(
      Uri.parse('$_kHiveBaseUrl/rest/v1/hive_jobs?id=eq.$jobId'),
      headers: {..._headers, 'Prefer': 'return=minimal'},
      body: jsonEncode(fields),
    );
  }

  // ── Cleanup ─────────────────────────────────────────────────

  @override
  void dispose() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}

// ── Helpers ───────────────────────────────────────────────────

void unawaited(Future<void> future) {
  future.catchError((e) => debugPrint('[HiveWorker] unawaited error: $e'));
}

extension _ListExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
