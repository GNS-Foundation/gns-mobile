/// Globe Crumbs App
/// 
/// Main app widget with initialization and routing.
/// 
/// Location: lib/app.dart

import 'package:flutter/material.dart';
import 'core/gns/identity_wallet.dart';
import 'core/profile/profile_service.dart';
import 'core/theme/theme_service.dart';
import 'navigation/main_navigation.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/widgets/floating_home_button.dart';

class GlobeCrumbsApp extends StatefulWidget {
  const GlobeCrumbsApp({super.key});
  
  @override
  State<GlobeCrumbsApp> createState() => _GlobeCrumbsAppState();
}

class _GlobeCrumbsAppState extends State<GlobeCrumbsApp> {
  final _wallet = IdentityWallet();
  final _profileService = ProfileService();
  final _themeService = ThemeService();
  bool _initialized = false;
  bool _hasIdentity = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
    _initialize();
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    try {
      await _themeService.initialize();
      _hasIdentity = await _wallet.checkIdentityExists();
      if (_hasIdentity) {
        await _wallet.initialize();
        await _profileService.initialize();
      }
      setState(() => _initialized = true);
    } catch (e) {
      setState(() { _error = e.toString(); _initialized = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Globe Crumbs',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeService.themeMode,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (!_initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    if (!_hasIdentity) {
      return WelcomeScreen(onCreateIdentity: _createIdentityWithHandle);
    }
    
    // Wrap main navigation with floating home button
    return FloatingHomeButton(
      child: MainNavigationScreen(
        wallet: _wallet,
        profileService: _profileService,
        onIdentityDeleted: _onIdentityDeleted,
      ),
    );
  }

  void _onIdentityDeleted() {
    setState(() {
      _hasIdentity = false;
    });
  }

  Future<void> _createIdentityWithHandle(String handle) async {
    final result = await _wallet.createIdentityWithHandle(handle);
    
    if (result.success) {
      await _wallet.initialize();
      if (mounted) {
        setState(() => _hasIdentity = true);
      }
      debugPrint('✅ Identity created: ${result.gnsId}');
      debugPrint('✅ Handle reserved: @${result.handle} (network: ${result.networkReserved})');
    } else {
      throw Exception(result.error ?? 'Failed to create identity');
    }
  }
}
