// ============================================================
// Phase 2: GCRUMBS Compute Job Builder
// File: lib/core/hive/compute_job.dart
//
// Constructs /v1/compute requests from GCRUMBS conversations.
// Used in conversation_screen.dart when chatting with @hai.
// ============================================================

import 'dart:convert';

/// Compute step types supported by the Hive Unified Compute API
enum ComputeStepType {
  inference,
  tileRender,
  imageProcess,
  sensorFusion,
}

/// A single step in a compute job
class ComputeStep {
  final String id;
  final ComputeStepType type;
  final String? dependsOn;
  final String? model;
  final List<Map<String, String>>? messages;
  final Map<String, dynamic>? context;
  // Tile render (Phase 3)
  final String? style;
  final String? centerCell;
  final int? rings;
  final int? zoom;
  final String? format;

  ComputeStep({
    required this.id,
    required this.type,
    this.dependsOn,
    this.model,
    this.messages,
    this.context,
    this.style,
    this.centerCell,
    this.rings,
    this.zoom,
    this.format,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'type': type.name == 'tileRender' ? 'tile_render'
            : type.name == 'imageProcess' ? 'image_process'
            : type.name == 'sensorFusion' ? 'sensor_fusion'
            : type.name,
    };
    if (dependsOn != null) map['depends_on'] = dependsOn;
    if (model != null) map['model'] = model;
    if (messages != null) map['messages'] = messages;
    if (context != null) map['context'] = context;
    if (style != null) map['style'] = style;
    if (centerCell != null) map['center_cell'] = centerCell;
    if (rings != null) map['rings'] = rings;
    if (zoom != null) map['zoom'] = zoom;
    if (format != null) map['format'] = format;
    return map;
  }
}

/// A compute job request sent to POST /v1/compute
class ComputeJobRequest {
  final String requesterPk;
  final String h3Cell;
  final List<ComputeStep> steps;
  final double budgetGns;
  final String? signature;

  ComputeJobRequest({
    required this.requesterPk,
    required this.h3Cell,
    required this.steps,
    this.budgetGns = 0.01,
    this.signature,
  });

  Map<String, dynamic> toJson() => {
    'requester_pk': requesterPk,
    'h3_cell': h3Cell,
    'steps': steps.map((s) => s.toJson()).toList(),
    'budget_gns': budgetGns,
    if (signature != null) 'signature': signature,
  };

  String toJsonString() => jsonEncode(toJson());
}

/// Parsed response from POST /v1/compute
class ComputeJobResponse {
  final String jobId;
  final String workerPk;
  final String h3Cell;
  final int epoch;
  final List<StepOutput> steps;
  final double totalGns;
  final String? stellarTx;
  final String jobHash;

  ComputeJobResponse({
    required this.jobId,
    required this.workerPk,
    required this.h3Cell,
    required this.epoch,
    required this.steps,
    required this.totalGns,
    this.stellarTx,
    required this.jobHash,
  });

  factory ComputeJobResponse.fromJson(Map<String, dynamic> json) {
    return ComputeJobResponse(
      jobId: json['job_id'] ?? '',
      workerPk: json['worker_pk'] ?? '',
      h3Cell: json['h3_cell'] ?? '',
      epoch: json['epoch'] ?? 0,
      steps: (json['steps'] as List?)
          ?.map((s) => StepOutput.fromJson(s))
          .toList() ?? [],
      totalGns: (json['settlement']?['total_gns'] ?? 0).toDouble(),
      stellarTx: json['settlement']?['stellar_tx'],
      jobHash: json['proof']?['job_hash'] ?? '',
    );
  }

  /// Get the inference text from the first inference step
  String? get inferenceText {
    final inf = steps.firstWhere(
      (s) => s.type == 'inference' && s.status == 'complete',
      orElse: () => StepOutput.empty(),
    );
    return inf.output['text'];
  }

  /// Get locations from inference output
  List<Map<String, dynamic>> get locations {
    final inf = steps.firstWhere(
      (s) => s.type == 'inference' && s.status == 'complete',
      orElse: () => StepOutput.empty(),
    );
    final locs = inf.output['locations'];
    if (locs is List) return locs.cast<Map<String, dynamic>>();
    return [];
  }
}

class StepOutput {
  final String id;
  final String type;
  final String status;
  final Map<String, dynamic> output;
  final int latencyMs;
  final String? error;

  StepOutput({
    required this.id,
    required this.type,
    required this.status,
    required this.output,
    required this.latencyMs,
    this.error,
  });

  factory StepOutput.empty() => StepOutput(
    id: '', type: '', status: 'failed', output: {}, latencyMs: 0,
  );

  factory StepOutput.fromJson(Map<String, dynamic> json) {
    return StepOutput(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      status: json['status'] ?? 'failed',
      output: json['output'] ?? {},
      latencyMs: json['latency_ms'] ?? 0,
      error: json['error'],
    );
  }
}

// ─── Smart Job Builder ──────────────────────

/// Builds a compute job from a user message.
/// Decides which steps to include based on message content.
class ComputeJobBuilder {
  static final _locationTriggers = [
    'where', 'near', 'nearby', 'restaurant', 'café', 'bar',
    'hotel', 'show me', 'map', 'directions', 'how to get',
    'around here', 'close to', 'in this area', 'walking distance',
    // Italian
    'dove', 'vicino', 'ristorante', 'mostrami', 'mappa',
  ];

  /// Build a compute job for a user message to @hai
  static ComputeJobRequest buildJob({
    required String userMessage,
    required String requesterPk,
    required String h3Cell,
    String? model,
  }) {
    final steps = <ComputeStep>[];

    // Always: inference step
    steps.add(ComputeStep(
      id: 'think',
      type: ComputeStepType.inference,
      model: model,
      messages: [
        {'role': 'user', 'content': userMessage},
      ],
      context: {'h3_cell': h3Cell},
    ));

    // Conditionally: tile render if location query (Phase 3)
    if (_isLocationQuery(userMessage)) {
      steps.add(ComputeStep(
        id: 'show',
        type: ComputeStepType.tileRender,
        dependsOn: 'think',
        centerCell: h3Cell,
        rings: 2,
        zoom: 15,
        style: 'osm-bright',
      ));
    }

    return ComputeJobRequest(
      requesterPk: requesterPk,
      h3Cell: h3Cell,
      steps: steps,
      budgetGns: 0.01,
    );
  }

  static bool _isLocationQuery(String msg) {
    final lower = msg.toLowerCase();
    return _locationTriggers.any((t) => lower.contains(t));
  }
}
