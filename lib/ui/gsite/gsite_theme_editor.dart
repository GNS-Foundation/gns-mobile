// ============================================================
// GNS gSITE THEME EDITOR
// ============================================================
// Location: lib/ui/gsite/gsite_theme_editor.dart
// Purpose: Visual theme customizer with live preview
//
// Features:
//   - Browse 8 preset themes with thumbnails
//   - Customize colors (primary, secondary, background, etc.)
//   - Pick fonts from Google Fonts allowlist
//   - Configure component styles (avatar shape, card style, etc.)
//   - Live WebView preview updates as user tweaks
//   - Save theme to gSite JSON
//
// Architecture:
//   ThemePresets → User selects base
//   → Color/Font/Component tweaks modify GSiteTheme in-memory
//   → ThemeEngine.generateCSS(theme) → injects into preview
//   → GSitePreviewRenderer uses theme CSS instead of defaults
//   → Save: theme JSON embedded in gSite or saved standalone
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/gsite/gsite_theme_engine.dart';
import '../../core/gsite/gsite_blocks.dart';
import '../../core/gsite/gsite_preview_renderer.dart';
import '../../core/theme/theme_service.dart';

// ============================================================
// MAIN THEME EDITOR SCREEN
// ============================================================

class GSiteThemeEditorScreen extends StatefulWidget {
  final Map<String, dynamic> gsiteJson; // Current gSite data for preview
  final GSiteTheme? currentTheme;
  final Function(GSiteTheme theme)? onThemeSelected;

  const GSiteThemeEditorScreen({
    super.key,
    required this.gsiteJson,
    this.currentTheme,
    this.onThemeSelected,
  });

  @override
  State<GSiteThemeEditorScreen> createState() => _GSiteThemeEditorScreenState();
}

class _GSiteThemeEditorScreenState extends State<GSiteThemeEditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late GSiteTheme _theme;
  WebViewController? _webViewController;

  // Editable color fields
  late String _primaryColor;
  late String _secondaryColor;
  late String _backgroundColor;
  late String _surfaceColor;
  late String _textColor;
  late String _accentLightColor;

  // Editable typography
  late String _displayFont;
  late String _bodyFont;
  late String _monoFont;

  // Editable components
  late String _avatarShape;
  late String _cardRadius;
  late String _buttonRadius;
  late String _sectionDivider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _theme = widget.currentTheme ?? PresetThemes.defaultTheme;
    _syncFromTheme();
  }

  void _syncFromTheme() {
    _primaryColor = _theme.tokens.colors.primary;
    _secondaryColor = _theme.tokens.colors.secondary;
    _backgroundColor = _theme.tokens.colors.background;
    _surfaceColor = _theme.tokens.colors.surface;
    _textColor = _theme.tokens.colors.onSurface;
    _accentLightColor = _theme.tokens.colors.surfaceVariant;
    _displayFont = _theme.tokens.typography.displayFont;
    _bodyFont = _theme.tokens.typography.bodyFont;
    _monoFont = _theme.tokens.typography.monoFont;
    _avatarShape = _theme.components.avatarShape;
    _cardRadius = _theme.components.cardRadius;
    _buttonRadius = _theme.components.buttonRadius;
    _sectionDivider = _theme.components.sectionDivider;
  }

  GSiteTheme _buildThemeFromEdits() {
    return GSiteTheme(
      id: _theme.id == PresetThemes.defaultTheme.id ? 'custom' : _theme.id,
      name: _theme.name,
      description: _theme.description,
      tokens: ThemeTokens(
        colors: ThemeColors(
          primary: _primaryColor,
          secondary: _secondaryColor,
          surface: _surfaceColor,
          surfaceVariant: _accentLightColor,
          background: _backgroundColor,
          onPrimary: _isLightColor(_primaryColor) ? '#1a1a2e' : '#ffffff',
          onSurface: _textColor,
          onBackground: _textColor,
        ),
        typography: ThemeTypography(
          displayFont: _displayFont,
          bodyFont: _bodyFont,
          monoFont: _monoFont,
        ),
      ),
      components: ThemeComponents(
        avatarShape: _avatarShape,
        cardRadius: _cardRadius,
        buttonRadius: _buttonRadius,
        sectionDivider: _sectionDivider,
      ),
      layout: _theme.layout,
    );
  }

  void _selectPreset(GSiteTheme preset) {
    setState(() {
      _theme = preset;
      _syncFromTheme();
    });
    _refreshPreview();
  }

  void _refreshPreview() {
    final theme = _buildThemeFromEdits();
    final themeCSS = ThemeEngine.generateCSS(theme);

    // Generate preview HTML with theme applied
    final html = GSitePreviewRenderer.renderFromJsonWithTheme(
      widget.gsiteJson,
      themeCSS,
    );

    _webViewController?.loadHtmlString(html);
  }

  void _applyTheme() {
    final theme = _buildThemeFromEdits();
    widget.onThemeSelected?.call(theme);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme Editor'),
        actions: [
          TextButton.icon(
            onPressed: _applyTheme,
            icon: const Icon(Icons.check),
            label: const Text('Apply'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Preview area (top 40%)
          Expanded(
            flex: 4,
            child: _buildPreview(),
          ),

          // Divider
          Container(
            height: 1,
            color: Colors.grey[300],
          ),

          // Editor area (bottom 60%)
          Expanded(
            flex: 6,
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: Colors.grey,
                  tabs: const [
                    Tab(text: 'Presets'),
                    Tab(text: 'Colors'),
                    Tab(text: 'Style'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPresetsTab(),
                      _buildColorsTab(),
                      _buildStyleTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PREVIEW
  // ============================================================

  Widget _buildPreview() {
    final theme = _buildThemeFromEdits();
    final themeCSS = ThemeEngine.generateCSS(theme);
    final html = GSitePreviewRenderer.renderFromJsonWithTheme(
      widget.gsiteJson,
      themeCSS,
    );

    return Stack(
      children: [
        Builder(
          builder: (context) {
            final controller = WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..setBackgroundColor(Colors.white)
              ..loadHtmlString(html);
            _webViewController = controller;
            return WebViewWidget(controller: controller);
          },
        ),
        // Floating theme name badge
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _theme.name,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PRESETS TAB
  // ============================================================

  Widget _buildPresetsTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: PresetThemes.all.length,
      itemBuilder: (context, index) {
        final preset = PresetThemes.all[index];
        final isSelected = preset.id == _theme.id;
        final colors = preset.tokens.colors;

        return GestureDetector(
          onTap: () => _selectPreset(preset),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _parseColor(colors.primary) : Colors.grey[300]!,
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Color swatches
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Container(color: _parseColor(colors.background)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              Expanded(child: Container(color: _parseColor(colors.primary))),
                              Expanded(child: Container(color: _parseColor(colors.secondary))),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(color: _parseColor(colors.onSurface)),
                        ),
                      ],
                    ),
                  ),
                ),
                // Label
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle, size: 16, color: _parseColor(colors.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // COLORS TAB
  // ============================================================

  Widget _buildColorsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _colorRow('Primary', _primaryColor, (c) {
          setState(() => _primaryColor = c);
          _refreshPreview();
        }),
        _colorRow('Secondary', _secondaryColor, (c) {
          setState(() => _secondaryColor = c);
          _refreshPreview();
        }),
        _colorRow('Background', _backgroundColor, (c) {
          setState(() => _backgroundColor = c);
          _refreshPreview();
        }),
        _colorRow('Surface', _surfaceColor, (c) {
          setState(() => _surfaceColor = c);
          _refreshPreview();
        }),
        _colorRow('Text', _textColor, (c) {
          setState(() => _textColor = c);
          _refreshPreview();
        }),
        const Divider(height: 24),
        // Quick palette presets
        const Text('Quick Palettes',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickPalettes.map((palette) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  _primaryColor = palette['primary']!;
                  _secondaryColor = palette['secondary']!;
                  _backgroundColor = palette['background']!;
                  _surfaceColor = palette['surface']!;
                  _textColor = palette['text']!;
                });
                _refreshPreview();
              },
              child: Container(
                width: 48,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Row(
                    children: [
                      Expanded(child: Container(color: _parseColor(palette['primary']!))),
                      Expanded(child: Container(color: _parseColor(palette['secondary']!))),
                      Expanded(child: Container(color: _parseColor(palette['background']!))),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _colorRow(String label, String hexColor, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: () => _showColorPicker(label, hexColor, onChanged),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _parseColor(hexColor),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: TextEditingController(text: hexColor),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onSubmitted: (v) {
                if (v.startsWith('#') && (v.length == 7 || v.length == 4)) {
                  onChanged(v);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(String label, String current, Function(String) onChanged) {
    // Simple color grid picker
    final colors = [
      '#2d5a9e', '#0369a1', '#0891b2', '#059669', '#2d6a4f', '#65a30d',
      '#b45309', '#d97706', '#e8614d', '#dc2626', '#db2777', '#9333ea',
      '#7c3aed', '#6366f1', '#000000', '#374151', '#6b7280', '#9ca3af',
      '#d1d5db', '#f3f4f6', '#ffffff', '#fafaf8', '#fffbf0', '#faf8ff',
      '#f0f9ff', '#f0faf4', '#fef7f4', '#fefce8',
    ];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors.map((hex) {
                final isSelected = hex == current;
                return GestureDetector(
                  onTap: () {
                    onChanged(hex);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _parseColor(hex),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? Colors.blue
                            : hex == '#ffffff' || hex == '#fafaf8'
                                ? Colors.grey[300]!
                                : Colors.transparent,
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                    child: isSelected
                        ? Icon(Icons.check,
                            size: 18,
                            color: _isLightColor(hex)
                                ? Colors.black
                                : Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STYLE TAB
  // ============================================================

  Widget _buildStyleTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Fonts
        const Text('Typography',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        _fontDropdown('Display Font', _displayFont, (v) {
          setState(() => _displayFont = v);
          _refreshPreview();
        }),
        const SizedBox(height: 8),
        _fontDropdown('Body Font', _bodyFont, (v) {
          setState(() => _bodyFont = v);
          _refreshPreview();
        }),
        const SizedBox(height: 8),
        _fontDropdown('Mono Font', _monoFont, (v) {
          setState(() => _monoFont = v);
          _refreshPreview();
        }),

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),

        // Components
        const Text('Components',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),

        _segmentedRow('Avatar Shape', _avatarShape, {
          'circle': '⭕ Circle',
          'rounded': '⬜ Rounded',
          'square': '◼ Square',
        }, (v) {
          setState(() => _avatarShape = v);
          _refreshPreview();
        }),

        const SizedBox(height: 12),

        _segmentedRow('Card Corners', _cardRadius, {
          'sm': 'Sharp',
          'md': 'Medium',
          'lg': 'Rounded',
          'xl': 'Pill',
        }, (v) {
          setState(() => _cardRadius = v);
          _refreshPreview();
        }),

        const SizedBox(height: 12),

        _segmentedRow('Button Style', _buttonRadius, {
          'sm': 'Sharp',
          'md': 'Medium',
          'lg': 'Rounded',
          'full': 'Pill',
        }, (v) {
          setState(() => _buttonRadius = v);
          _refreshPreview();
        }),

        const SizedBox(height: 12),

        _segmentedRow('Section Dividers', _sectionDivider, {
          'line': '─ Line',
          'space': '⌴ Space',
          'none': '⊘ None',
        }, (v) {
          setState(() => _sectionDivider = v);
          _refreshPreview();
        }),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _fontDropdown(String label, String current, Function(String) onChanged) {
    const fonts = [
      'Source Sans 3', 'Playfair Display', 'Inter', 'Roboto', 'Open Sans',
      'Lato', 'Montserrat', 'Poppins', 'Merriweather', 'Lora',
      'JetBrains Mono', 'Fira Code', 'Source Code Pro',
    ];

    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: fonts.contains(current) ? current : fonts.first,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            items: fonts
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _segmentedRow(String label, String current,
      Map<String, String> options, Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Row(
          children: options.entries.map((entry) {
            final isSelected = entry.key == current;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  margin: EdgeInsets.only(
                    right: entry.key != options.keys.last ? 6 : 0,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _parseColor(_primaryColor).withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? _parseColor(_primaryColor)
                          : Colors.grey[300]!,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    entry.value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? _parseColor(_primaryColor)
                          : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ============================================================
  // QUICK PALETTES
  // ============================================================

  static final List<Map<String, String>> _quickPalettes = [
    {'primary': '#2d5a9e', 'secondary': '#6c757d', 'background': '#fafaf8', 'surface': '#ffffff', 'text': '#1a1a2e'},
    {'primary': '#60a5fa', 'secondary': '#a78bfa', 'background': '#0f172a', 'surface': '#1e293b', 'text': '#e2e8f0'},
    {'primary': '#e8614d', 'secondary': '#f4a261', 'background': '#fffaf8', 'surface': '#ffffff', 'text': '#2d1f1a'},
    {'primary': '#2d6a4f', 'secondary': '#95d5b2', 'background': '#f5faf7', 'surface': '#ffffff', 'text': '#1b2e22'},
    {'primary': '#7c3aed', 'secondary': '#a78bfa', 'background': '#faf8ff', 'surface': '#ffffff', 'text': '#1e1b2e'},
    {'primary': '#000000', 'secondary': '#ff3366', 'background': '#ffffff', 'surface': '#ffffff', 'text': '#000000'},
    {'primary': '#b45309', 'secondary': '#d97706', 'background': '#fffbf0', 'surface': '#ffffff', 'text': '#292524'},
    {'primary': '#0369a1', 'secondary': '#0891b2', 'background': '#f8fafc', 'surface': '#ffffff', 'text': '#0c1524'},
  ];

  // ============================================================
  // HELPERS
  // ============================================================

  Color _parseColor(String hex) {
    if (!hex.startsWith('#')) return Colors.grey;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6) return Colors.grey;
    return Color(int.parse('FF$hex', radix: 16));
  }

  bool _isLightColor(String hex) {
    final c = _parseColor(hex);
    return (c.red * 0.299 + c.green * 0.587 + c.blue * 0.114) > 186;
  }
}

// ============================================================
// EXTENSION: Add theme-aware rendering to GSitePreviewRenderer
// ============================================================
// This extension adds a method that accepts custom theme CSS
// and injects it into the rendered HTML, overriding defaults.
// ============================================================

extension ThemedPreviewRenderer on GSitePreviewRenderer {
  /// Render HTML with custom theme CSS injected
  /// This replaces the default <style> block with theme-generated CSS
  static String renderWithTheme(
      Map<String, dynamic> json, String themeCSS) {
    return GSitePreviewRenderer.renderFromJsonWithTheme(json, themeCSS);
  }
}

// ============================================================
// Add this static method to GSitePreviewRenderer:
// (Or use as standalone function that wraps the renderer)
// ============================================================

extension GSitePreviewRendererThemed on GSitePreviewRenderer {
  // Placeholder — the actual implementation is in the updated
  // gsite_preview_renderer.dart file
}
