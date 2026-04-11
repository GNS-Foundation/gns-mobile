// ============================================================
// HIVE WORKER SCREEN — GCRUMBS Mobile Worker Mode
//
// "Your phone is a bee in the Hive.
//  Every job you relay earns GNS tokens."
//
// Location: lib/ui/hive/hive_worker_screen.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/hive/hive_worker_service.dart';
import '../../core/gns/identity_wallet.dart';

class HiveWorkerScreen extends StatefulWidget {
  final IdentityWallet wallet;

  const HiveWorkerScreen({super.key, required this.wallet});

  @override
  State<HiveWorkerScreen> createState() => _HiveWorkerScreenState();
}

class _HiveWorkerScreenState extends State<HiveWorkerScreen>
    with TickerProviderStateMixin {
  final _service = HiveWorkerService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // Design tokens
  static const _cyan = Color(0xFF0099CC);
  static const _green = Color(0xFF00C853);
  static const _amber = Color(0xFFFFAB00);
  static const _bg = Color(0xFF06090F);
  static const _bg2 = Color(0xFF0C1219);
  static const _bg3 = Color(0xFF121A25);
  static const _border = Color(0x12FFFFFF);
  static const _textMuted = Color(0xFF5A7290);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initWorker();
    _service.addListener(_onStatusChanged);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _service.removeListener(_onStatusChanged);
    super.dispose();
  }

  void _onStatusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initWorker() async {
    final pk = widget.wallet.publicKey;
    if (pk == null) return;
    final handle = await widget.wallet.getCurrentHandle();
    // Use a default h3 cell — ideally from last known location
    await _service.initialize(
      workerPk: pk,
      handle: handle,
      h3Cell: '861e8050fffffff',
    );
  }

  Future<void> _toggleWorker(bool value) async {
    HapticFeedback.mediumImpact();
    await _service.setEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _service.status;

    return Scaffold(
      backgroundColor: isDark ? _bg : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? _bg : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: isDark ? Colors.white : Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text(
              'Hive Worker',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            if (status.running)
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Opacity(
                  opacity: _pulseAnim.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeroCard(status, isDark),
          const SizedBox(height: 16),
          _buildToggleCard(status, isDark),
          const SizedBox(height: 16),
          _buildStatsRow(status, isDark),
          const SizedBox(height: 16),
          _buildHowItWorks(isDark),
          const SizedBox(height: 16),
          _buildEarningsCard(status, isDark),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Hero card ──────────────────────────────────────────────

  Widget _buildHeroCard(HiveWorkerStatus status, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF0C1A2E), const Color(0xFF061219)]
              : [const Color(0xFFE8F5E9), const Color(0xFFE3F2FD)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status.running ? _green.withOpacity(0.3) : _border,
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _cyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('⬡', style: TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GEIANT Hive',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: _cyan,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your phone is a bee',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Every AI request routed through your phone earns GNS tokens. '
            'Your device contributes to a decentralized inference network '
            'powered by people — not data centres.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? _textMuted : Colors.black54,
              height: 1.6,
            ),
          ),
          if (status.h3Cell != null) ...[
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _cyan.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _cyan.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hexagon_outlined,
                      color: _cyan, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    'H3 Cell: ${status.h3Cell!.substring(0, 12)}…',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: _cyan,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Toggle card ────────────────────────────────────────────

  Widget _buildToggleCard(HiveWorkerStatus status, bool isDark) {
    final bgCard = isDark ? _bg2 : const Color(0xFFF8F9FA);
    return Container(
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status.running
              ? _green.withOpacity(0.3)
              : isDark
                  ? _border
                  : Colors.grey.shade200,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.running
                      ? 'Worker Active'
                      : status.enabled
                          ? 'Starting…'
                          : 'Worker Inactive',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.running
                      ? 'Polling for jobs every 30s'
                      : 'Enable to earn GNS while idle',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? _textMuted : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: status.enabled,
            onChanged: _toggleWorker,
            activeColor: _green,
          ),
        ],
      ),
    );
  }

  // ── Stats row ──────────────────────────────────────────────

  Widget _buildStatsRow(HiveWorkerStatus status, bool isDark) {
    return Row(
      children: [
        _buildStatCard(
          icon: '◆',
          label: 'GNS Earned',
          value: status.tokensEarned.toStringAsFixed(4),
          color: _green,
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          icon: '→',
          label: 'Jobs Relayed',
          value: status.jobsRelayed.toString(),
          color: _cyan,
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          icon: '⬡',
          label: 'Trust Tier',
          value: _capitalize(status.trustTier),
          color: _amber,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? _bg2 : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? _border : Colors.grey.shade200,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: TextStyle(fontSize: 16, color: color)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.5,
                color: isDark ? _textMuted : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── How it works ───────────────────────────────────────────

  Widget _buildHowItWorks(bool isDark) {
    final steps = [
      ('01', 'You enable Worker Mode', _green),
      ('02', 'Your phone joins the Hive swarm', _cyan),
      ('03', 'An AI request arrives in your H3 cell', _cyan),
      ('04', 'Your phone relays it to a compute node', _amber),
      ('05', 'Result is returned + signed', _cyan),
      ('06', 'GNS tokens credited to your identity', _green),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? _bg2 : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? _border : Colors.grey.shade200,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HOW IT WORKS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 16),
          ...steps.map((s) => _buildStep(s.$1, s.$2, s.$3, isDark)),
        ],
      ),
    );
  }

  Widget _buildStep(
      String num, String text, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                num,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Earnings card ──────────────────────────────────────────

  Widget _buildEarningsCard(HiveWorkerStatus status, bool isDark) {
    const routingFeePercent = 20;
    const exampleJobsPerDay = 100;
    const exampleRewardPerJob = 0.01;
    const dailyEstimate =
        exampleJobsPerDay * exampleRewardPerJob * routingFeePercent / 100;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? _bg3 : const Color(0xFFF0FAF0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined, color: _green, size: 20),
              const SizedBox(width: 8),
              Text(
                'EARNINGS MODEL',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: _green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildEarningsRow(
            'Routing fee per job',
            '$routingFeePercent% of job reward',
            isDark,
          ),
          _buildEarningsRow(
            'Typical reward per job',
            '0.0100 GNS',
            isDark,
          ),
          _buildEarningsRow(
            'Your routing fee',
            '0.0020 GNS per job',
            isDark,
          ),
          const Divider(color: _border, height: 24),
          _buildEarningsRow(
            'Est. daily earnings (100 jobs)',
            '${dailyEstimate.toStringAsFixed(4)} GNS',
            isDark,
            highlight: true,
          ),
          const SizedBox(height: 12),
          Text(
            'As the network grows and more devices join, '
            'job volume increases and earnings scale with it. '
            'Every device you own adds to your @handle cluster.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? _textMuted : Colors.black45,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsRow(String label, String value, bool isDark,
      {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  highlight ? FontWeight.w800 : FontWeight.w600,
              fontFamily: 'monospace',
              color: highlight
                  ? _green
                  : isDark
                      ? Colors.white
                      : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
