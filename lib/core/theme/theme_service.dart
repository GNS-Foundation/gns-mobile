/// Theme Service - Light/Dark Mode Support
/// 
/// Provides theme switching with persistence.
/// 
/// Location: lib/core/theme/theme_service.dart

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const _storageKey = 'gns_theme_mode';
  final _storage = const FlutterSecureStorage();
  
  ThemeMode _themeMode = ThemeMode.dark;
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get isLight => _themeMode == ThemeMode.light;

  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      final stored = await _storage.read(key: _storageKey);
      if (stored == 'light') {
        _themeMode = ThemeMode.light;
      } else {
        _themeMode = ThemeMode.dark;
      }
    } catch (e) {
      _themeMode = ThemeMode.dark;
    }
    
    _initialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    
    _themeMode = mode;
    notifyListeners();
    
    await _storage.write(
      key: _storageKey,
      value: mode == ThemeMode.light ? 'light' : 'dark',
    );
  }

  Future<void> toggleTheme() async {
    await setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}

// ==================== APP THEMES ====================

class AppTheme {
  // ==================== DARK THEME COLORS ====================
  static const darkBackground = Color(0xFF0D1117);
  static const darkSurface = Color(0xFF161B22);
  static const darkSurfaceLight = Color(0xFF21262D);
  static const darkBorder = Color(0xFF30363D);
  static const darkTextPrimary = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0xFF8B949E);
  static const darkTextMuted = Color(0xFF6E7681);

  // ==================== LIGHT THEME COLORS ====================
  static const lightBackground = Color(0xFFF6F8FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceLight = Color(0xFFF0F3F6);
  static const lightBorder = Color(0xFFD0D7DE);
  static const lightTextPrimary = Color(0xFF1F2328);
  static const lightTextSecondary = Color(0xFF656D76);
  static const lightTextMuted = Color(0xFF8C959F);

  // ==================== SHARED COLORS ====================
  static const primary = Color(0xFF3B82F6);
  static const secondary = Color(0xFF10B981);
  static const accent = Color(0xFF8B5CF6);
  static const warning = Color(0xFFFBBF24);
  static const error = Color(0xFFEF4444);

  // ==================== DARK THEME ====================
  static ThemeData get dark => ThemeData.dark().copyWith(
    scaffoldBackgroundColor: darkBackground,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      surface: darkSurface,
      error: error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: darkTextPrimary,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBackground,
      elevation: 0,
      centerTitle: true,
      foregroundColor: darkTextPrimary,
    ),
    cardTheme: CardTheme(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: darkBorder, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      hintStyle: const TextStyle(color: darkTextMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return darkTextMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary.withOpacity(0.5);
        return darkSurfaceLight;
      }),
    ),
    dividerTheme: const DividerThemeData(color: darkBorder),
    dialogTheme: DialogTheme(
      backgroundColor: darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkSurface,
      selectedItemColor: primary,
      unselectedItemColor: darkTextMuted,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkSurface,
      contentTextStyle: const TextStyle(color: darkTextPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
    ),
  );

  // ==================== LIGHT THEME ====================
  static ThemeData get light => ThemeData.light().copyWith(
    scaffoldBackgroundColor: lightBackground,
    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: secondary,
      surface: lightSurface,
      error: error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: lightTextPrimary,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: lightSurface,
      elevation: 0,
      centerTitle: true,
      foregroundColor: lightTextPrimary,
      iconTheme: IconThemeData(color: lightTextPrimary),
    ),
    cardTheme: CardTheme(
      color: lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: lightBorder, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSurfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      hintStyle: const TextStyle(color: lightTextMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return lightTextMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary.withOpacity(0.5);
        return lightBorder;
      }),
    ),
    dividerTheme: const DividerThemeData(color: lightBorder),
    dialogTheme: DialogTheme(
      backgroundColor: lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: lightSurface,
      selectedItemColor: primary,
      unselectedItemColor: lightTextMuted,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: lightSurface,
      contentTextStyle: const TextStyle(color: lightTextPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
    ),
  );

  // ==================== HELPER METHODS (context-aware) ====================
  
  /// Get colors based on current brightness
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkBackground : lightBackground;
  
  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkSurface : lightSurface;
  
  static Color surfaceLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkSurfaceLight : lightSurfaceLight;
  
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkBorder : lightBorder;
  
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTextPrimary : lightTextPrimary;
  
  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTextSecondary : lightTextSecondary;
  
  static Color textMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTextMuted : lightTextMuted;

  // ==================== SHORTCUT CONSTANTS ====================
  // For use in const contexts or where BuildContext is not available.
  // Note: These always return dark theme colors. For theme-aware colors,
  // use the methods above with (context).
  
  static const Color backgroundConst = darkBackground;
  static const Color surfaceConst = darkSurface;
  static const Color surfaceLightConst = darkSurfaceLight;
  static const Color borderConst = darkBorder;
  static const Color textPrimaryConst = darkTextPrimary;
  static const Color textSecondaryConst = darkTextSecondary;
  static const Color textMutedConst = darkTextMuted;
}
