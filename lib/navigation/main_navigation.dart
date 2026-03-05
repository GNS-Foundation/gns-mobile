/// Main Navigation Screen — Tier-Based Dynamic Navigation
///
/// Tabs unlock progressively as user collects breadcrumbs:
///   🌱 Seedling  (0+)    → Home | Journey | Settings
///   🌿 Explorer  (10+)   → same + handle features
///   🧭 Navigator (100+)  → + Messages | Contacts
///   🏔️ Trailblazer (250+)→ + History (payments via Home)
///
/// Location: lib/navigation/main_navigation.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../core/gns/identity_wallet.dart';
import '../core/profile/profile_service.dart';
import '../core/financial/payment_service.dart';
import '../core/tier/tier_gate.dart';
import '../core/theme/theme_service.dart';
import '../ui/home/home_tab.dart';
import '../ui/journey/journey_tab.dart';
import '../ui/contacts/contacts_tab.dart';
import '../ui/settings/settings_tab.dart';
import '../ui/screens/history_screen.dart';
import '../ui/messages/thread_list_screen.dart';
import '../ui/financial/payment_received_sheet.dart';

class MainNavigationScreen extends StatefulWidget {
  final IdentityWallet wallet;
  final ProfileService profileService;
  final VoidCallback onIdentityDeleted;

  const MainNavigationScreen({
    super.key,
    required this.wallet,
    required this.profileService,
    required this.onIdentityDeleted,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  PaymentService? _paymentService;
  StreamSubscription? _incomingPaymentSub;
  final _tierGate = TierGate();
  GnsTier? _lastCelebratedTier;

  @override
  void initState() {
    super.initState();
    _tierGate.addListener(_onTierChanged);
    _initPayments();
  }

  @override
  void dispose() {
    _incomingPaymentSub?.cancel();
    _tierGate.removeListener(_onTierChanged);
    super.dispose();
  }

  // ─── Tier ────────────────────────────────────────────────────────────────

  void _onTierChanged() {
    if (!mounted) return;
    final tabs = _buildTabs();
    final safeIndex = _currentIndex.clamp(0, tabs.length - 1);
    setState(() => _currentIndex = safeIndex);
    _maybeCelebrateTierUp();
  }

  GnsTier get _tier => _tierGate.currentTier;

  // ─── Payments ────────────────────────────────────────────────────────────

  Future<void> _initPayments() async {
    try {
      _paymentService = PaymentService.instance(widget.wallet);
      await _paymentService!.initialize();
      _paymentService!.startPolling();
      _incomingPaymentSub = _paymentService!.incomingPayments.listen((incoming) {
        PaymentReceivedSheet.show(
          context,
          incomingPayment: incoming,
          paymentService: _paymentService!,
        );
      });
    } catch (e) {
      debugPrint('Payment init error: $e');
    }
  }

  // ─── Tab Definitions ─────────────────────────────────────────────────────

  List<_TabItem> _buildTabs() {
    return [
      _TabItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
        body: HomeTab(
          wallet: widget.wallet,
          profileService: widget.profileService,
        ),
      ),

      if (_tier.canSendMessages)
        _TabItem(
          icon: Icons.chat_bubble_outline,
          activeIcon: Icons.chat_bubble,
          label: 'Messages',
          body: const ThreadListScreen(),
        ),

      if (_tier.canViewContacts)
        _TabItem(
          icon: Icons.people_outline,
          activeIcon: Icons.people,
          label: 'Contacts',
          body: ContactsTab(profileService: widget.profileService),
        ),

      if (_tier.canViewHistory)
        _TabItem(
          icon: Icons.history_outlined,
          activeIcon: Icons.history,
          label: 'History',
          body: HistoryScreen(
            wallet: widget.wallet,
            paymentService: _paymentService,
          ),
        ),

      _TabItem(
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore,
        label: _tier.displayName,
        body: JourneyTab(wallet: widget.wallet),
      ),

      _TabItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: 'Settings',
        body: SettingsTab(
          wallet: widget.wallet,
          onIdentityDeleted: widget.onIdentityDeleted,
        ),
      ),
    ];
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tabs = _buildTabs();
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: tabs.map((t) => t.body).toList(),
      ),
      bottomNavigationBar: _buildBottomNav(tabs),
    );
  }

  Widget _buildBottomNav(List<_TabItem> tabs) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border(context), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _tier.color,
        items: tabs.map((t) => BottomNavigationBarItem(
          icon: Icon(t.icon),
          activeIcon: Icon(t.activeIcon),
          label: t.label,
        )).toList(),
      ),
    );
  }

  // ─── Tier-Up Celebration ─────────────────────────────────────────────────

  void _maybeCelebrateTierUp() {
    if (_lastCelebratedTier == null) {
      _lastCelebratedTier = _tier;
      return;
    }
    if (_tier.level > _lastCelebratedTier!.level) {
      _lastCelebratedTier = _tier;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Text(_tier.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${_tier.displayName} unlocked!',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(_tier.description,
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: _tier.color,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}

// ─── Internal Tab Model ──────────────────────────────────────────────────────

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget body;

  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.body,
  });
}
