/// Main Navigation Screen
/// 
/// Bottom navigation with 5 tabs: Home, Messages, Contacts, History, Settings
/// Globe timeline is now integrated into Messages tab via segmented control.
/// 
/// Location: lib/navigation/main_navigation.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../core/gns/identity_wallet.dart';
import '../core/profile/profile_service.dart';
import '../core/financial/payment_service.dart';
import '../core/theme/theme_service.dart';
import '../core/calls/call_service.dart';
import '../core/calls/call_screen.dart';
import '../ui/home/home_tab.dart';
import '../ui/contacts/contacts_tab.dart';
import '../ui/settings/settings_tab.dart';
import '../ui/screens/history_screen.dart';
import '../ui/messages/thread_list_screen.dart';
import '../ui/financial/send_money_screen.dart';
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
  StreamSubscription? _incomingCallSub;

  @override
  void initState() {
    super.initState();
    super.initState();
    _initPayments();
    
    // ✅ Global Call Listener
    _incomingCallSub = CallService().callStream.listen((info) {
      if (mounted && info.state == CallState.incomingRinging) {
        CallScreen.show(
          context,
          isIncoming: true,
        );
      }
    });
  }

  @override
  void dispose() {
    _incomingPaymentSub?.cancel();
    _incomingCallSub?.cancel();
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
      body: Stack(
        children: [
          // Main content - 5 tabs (Globe is now inside Messages)
          IndexedStack(
            index: _currentIndex,
            children: [
              HomeTab(
                wallet: widget.wallet,
                profileService: widget.profileService,
                paymentService: _paymentService,
              ),
              const ThreadListScreen(),  // Messages + Globe (segmented)
              ContactsTab(profileService: widget.profileService),
              HistoryScreen(
                wallet: widget.wallet,
                paymentService: _paymentService,
              ),
              SettingsTab(
                wallet: widget.wallet,
                onIdentityDeleted: widget.onIdentityDeleted,
              ),
            ],
          ),
          
          // Action buttons - ONLY on Contacts tab (index 2)
          if (_currentIndex == 2)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildActionButtons(),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ==================== ACTION BUTTONS (Contacts only) ====================
  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Send Money (coin icon)
          _buildActionButton(
            icon: Icons.monetization_on_outlined,
            tooltip: 'Send Money',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
              );
            },
          ),
          
          // Right: Compose Message (pencil icon) - switches to Messages tab
          _buildActionButton(
            icon: Icons.edit_outlined,
            tooltip: 'New Message',
            onTap: () {
              setState(() => _currentIndex = 1); // Switch to Messages tab
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.surface(context),
      borderRadius: BorderRadius.circular(28),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: Tooltip(
            message: tooltip,
            child: Icon(
              icon,
              color: AppTheme.primary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border(context), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
