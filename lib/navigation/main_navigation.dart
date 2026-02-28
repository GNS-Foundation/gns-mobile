/// Main Navigation Screen — Phase 1
/// 
/// 3 tabs: Home, Journey, Settings
/// Tier-colored accent on nav bar reflects current tier.
/// 
/// Location: lib/navigation/main_navigation.dart

import 'package:flutter/material.dart';
import '../core/gns/identity_wallet.dart';
import '../core/profile/profile_service.dart';
import '../core/tier_gate.dart';
import '../core/theme/theme_service.dart';
import '../ui/home/home_tab.dart';
import '../ui/journey/journey_tab.dart';
import '../ui/settings/settings_tab.dart';

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
  final _tierGate = TierGate();

  @override
  void initState() {
    super.initState();
    _tierGate.addListener(_onTierChanged);
  }

  @override
  void dispose() {
    _tierGate.removeListener(_onTierChanged);
    super.dispose();
  }

  void _onTierChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeTab(
            wallet: widget.wallet,
            profileService: widget.profileService,
          ),
          JourneyTab(wallet: widget.wallet),
          SettingsTab(
            wallet: widget.wallet,
            onIdentityDeleted: widget.onIdentityDeleted,
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final tierColor = Color(_tierGate.currentTier.colorValue);
    
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border(context), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: tierColor,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.explore_outlined),
            activeIcon: const Icon(Icons.explore),
            label: _tierGate.currentTier.displayName,
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
