/// Chain Export Utility
/// 
/// Exports the full breadcrumb chain as JSON for offline
/// analysis by the Criticality Engine (trip-verifier).
///
/// Usage: Add an "Export Chain" button to the debug screen,
/// or call ChainExporter.exportAndShare(context) from anywhere.
///
/// Location: lib/core/chain/chain_exporter.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'chain_storage.dart';

class ChainExporter {
  /// Export the full chain as JSON and trigger the share sheet.
  /// Returns the number of breadcrumbs exported.
  static Future<int> exportAndShare(BuildContext context) async {
    final storage = ChainStorage();
    await storage.initialize();

    // Get all breadcrumbs in order
    final blocks = await storage.getFullChain();
    
    if (blocks.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No breadcrumbs to export')),
        );
      }
      return 0;
    }

    // Convert to JSON array matching the Rust Breadcrumb struct
    final jsonList = blocks.map((block) {
      return {
        'index': block.index,
        'identity_public_key': block.identityPublicKey,
        'timestamp': block.timestamp.toUtc().toIso8601String(),
        'location_cell': block.locationCell,
        'location_resolution': block.locationResolution,
        'context_digest': block.contextDigest,
        'previous_hash': block.previousHash,
        'meta_flags': block.metaFlags,
        'signature': block.signature,
        'block_hash': block.blockHash,
      };
    }).toList();

    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);

    // Write to temp file
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/chain_export_$timestamp.json');
    await file.writeAsString(jsonString);

    // Share via system share sheet (AirDrop, email, etc.)
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'GNS Breadcrumb Chain Export',
      text: '${blocks.length} breadcrumbs exported',
    );

    debugPrint('Exported ${blocks.length} breadcrumbs to ${file.path}');
    return blocks.length;
  }

  /// Export to a file path without sharing (for automated use).
  static Future<String> exportToFile(String outputPath) async {
    final storage = ChainStorage();
    await storage.initialize();

    final blocks = await storage.getFullChain();
    
    final jsonList = blocks.map((block) {
      return {
        'index': block.index,
        'identity_public_key': block.identityPublicKey,
        'timestamp': block.timestamp.toUtc().toIso8601String(),
        'location_cell': block.locationCell,
        'location_resolution': block.locationResolution,
        'context_digest': block.contextDigest,
        'previous_hash': block.previousHash,
        'meta_flags': block.metaFlags,
        'signature': block.signature,
        'block_hash': block.blockHash,
      };
    }).toList();

    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonList);
    final file = File(outputPath);
    await file.writeAsString(jsonString);

    return file.path;
  }
}

/// Widget: "Export Chain" button for the debug screen.
/// Drop this anywhere in a Column or ListView.
class ExportChainButton extends StatelessWidget {
  const ExportChainButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () async {
        final count = await ChainExporter.exportAndShare(context);
        if (context.mounted && count > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported $count breadcrumbs')),
          );
        }
      },
      icon: const Icon(Icons.download),
      label: const Text('Export Chain (JSON)'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
    );
  }
}
