/// Main Navigation Screen — Trajectory Map Edition
/// 
/// 4-tab navigation: Map | Badges | Digest | Profile
/// Map is the home screen. Protocol features live in Profile > Advanced.
///
/// Location: lib/navigation/main_navigation.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../core/gns/identity_wallet.dart';
import '../core/profile/profile_service.dart';
import '../core/financial/payment_service.dart';
import '../core/theme/theme_service.dart';
import '../ui/trajectory/trajectory_map_tab.dart';
import '../ui/trajectory/badges_tab.dart';
import '../ui/trajectory/digest_tab.dart';
import '../ui/trajectory/profile_tab.dart';
import '../ui/messages/unified_inbox_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _initPayments();
  }

  @override
  void dispose() {
    _incomingPaymentSub?.cancel();
    super.dispose();
  }

  Future<void> _initPayments() async {
    try {
      _paymentService = PaymentService.instance(widget.wallet);
      await _paymentService!.initialize();
      _paymentService!.startPolling();
      
      // Listen for incoming payments globally
      _incomingPaymentSub = _paymentService!.incomingPayments.listen((incoming) {
        _showIncomingPayment(incoming);
      });
    } catch (e) {
      debugPrint('Payment init error: $e');
    }
  }

  void _showIncomingPayment(IncomingPayment incoming) {
    PaymentReceivedSheet.show(
      context,
      incomingPayment: incoming,
      paymentService: _paymentService!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Map (home)
          TrajectoryMapTab(wallet: widget.wallet),

          // Tab 1: Chat
          const UnifiedInboxScreen(),

          // Tab 2: Badges
          const BadgesTab(),

          // Tab 3: Digest
          const DigestTab(),

          // Tab 4: Profile (absorbs identity, settings, wallet, advanced)
          ProfileTab(
            wallet: widget.wallet,
            profileService: widget.profileService,
            paymentService: _paymentService,
            onIdentityDeleted: widget.onIdentityDeleted,
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.border(context), width: 1),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events_outlined),
            activeIcon: Icon(Icons.emoji_events),
            label: 'Badges',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_stories_outlined),
            activeIcon: Icon(Icons.auto_stories),
            label: 'Digest',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
