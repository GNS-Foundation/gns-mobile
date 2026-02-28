// ============================================================
// GNS gSITE THEME ENGINE
// ============================================================
// Location: lib/core/gsite/gsite_theme_engine.dart
// Purpose: Theme models, 8 preset themes, CSS generator
//
// Architecture:
//   GSiteTheme (JSON) → ThemeEngine.generateCSS() → CSS Variables
//   → Renderer applies variables → Same HTML, different look
//
// Aligns with: theme_schema.json (PANTHERA Theme Schema v1)
// ============================================================

import 'dart:convert';

// ============================================================
// THEME MODEL (mirrors theme_schema.json)
// ============================================================

class GSiteTheme {
  final String id;
  final String name;
  final String? description;
  final String version;
  final String? author;
  final String license; // free, standard, premium, exclusive
  final ThemePrice? price;
  final List<String> entityTypes;
  final List<String> categories;
  final ThemeTokens tokens;
  final ThemeComponents components;
  final ThemeLayout layout;
  final DarkModeConfig? darkMode;
  final String? thumbnailUrl;

  const GSiteTheme({
    required this.id,
    required this.name,
    this.description,
    this.version = '1.0.0',
    this.author,
    this.license = 'free',
    this.price,
    this.entityTypes = const ['Person', 'Business', 'Store', 'Organization'],
    this.categories = const [],
    required this.tokens,
    required this.components,
    required this.layout,
    this.darkMode,
    this.thumbnailUrl,
  });

  factory GSiteTheme.fromJson(Map<String, dynamic> json) => GSiteTheme(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    version: json['version'] as String? ?? '1.0.0',
    author: json['author'] as String?,
    license: json['license'] as String? ?? 'free',
    price: json['price'] != null ? ThemePrice.fromJson(json['price']) : null,
    entityTypes: (json['entityTypes'] as List<dynamic>?)?.cast<String>() ?? ['Person'],
    categories: (json['categories'] as List<dynamic>?)?.cast<String>() ?? [],
    tokens: ThemeTokens.fromJson(json['tokens'] as Map<String, dynamic>),
    components: json['components'] != null
        ? ThemeComponents.fromJson(json['components'] as Map<String, dynamic>)
        : ThemeComponents.defaults(),
    layout: json['layout'] != null
        ? ThemeLayout.fromJson(json['layout'] as Map<String, dynamic>)
        : ThemeLayout.defaults(),
    darkMode: json['darkMode'] != null
        ? DarkModeConfig.fromJson(json['darkMode'] as Map<String, dynamic>)
        : null,
    thumbnailUrl: json['preview']?['thumbnail'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'version': version,
    if (author != null) 'author': author,
    'license': license,
    if (price != null) 'price': price!.toJson(),
    'entityTypes': entityTypes,
    'categories': categories,
    'tokens': tokens.toJson(),
    'components': components.toJson(),
    'layout': layout.toJson(),
    if (darkMode != null) 'darkMode': darkMode!.toJson(),
  };
}

class ThemePrice {
  final double amount;
  final String currency;
  const ThemePrice({required this.amount, this.currency = 'GNS'});
  factory ThemePrice.fromJson(Map<String, dynamic> json) => ThemePrice(
    amount: (json['amount'] as num).toDouble(),
    currency: json['currency'] as String? ?? 'GNS',
  );
  Map<String, dynamic> toJson() => {'amount': amount, 'currency': currency};
}

// ============================================================
// DESIGN TOKENS
// ============================================================

class ThemeColors {
  final String primary;
  final String primaryVariant;
  final String secondary;
  final String surface;
  final String surfaceVariant;
  final String background;
  final String onPrimary;
  final String onSurface;
  final String onBackground;
  final String error;
  final String success;
  final String warning;
  final String divider;
  final String textMuted;
  final String trustHigh;
  final String trustMedium;
  final String trustLow;

  const ThemeColors({
    required this.primary,
    this.primaryVariant = '',
    required this.secondary,
    required this.surface,
    this.surfaceVariant = '',
    required this.background,
    required this.onPrimary,
    required this.onSurface,
    required this.onBackground,
    this.error = '#dc3545',
    this.success = '#2a9d5c',
    this.warning = '#d4a017',
    this.divider = '#e2e4ea',
    this.textMuted = '#8b8da3',
    this.trustHigh = '#2d5a9e',
    this.trustMedium = '#2a9d5c',
    this.trustLow = '#d4a017',
  });

  factory ThemeColors.fromJson(Map<String, dynamic> json) => ThemeColors(
    primary: json['primary'] as String? ?? '#2d5a9e',
    primaryVariant: json['primaryVariant'] as String? ?? '',
    secondary: json['secondary'] as String? ?? '#6c757d',
    surface: json['surface'] as String? ?? '#ffffff',
    surfaceVariant: json['surfaceVariant'] as String? ?? '#f8f9fa',
    background: json['background'] as String? ?? '#fafaf8',
    onPrimary: json['onPrimary'] as String? ?? '#ffffff',
    onSurface: json['onSurface'] as String? ?? '#1a1a2e',
    onBackground: json['onBackground'] as String? ?? '#1a1a2e',
    error: json['error'] as String? ?? '#dc3545',
    success: json['success'] as String? ?? '#2a9d5c',
    warning: json['warning'] as String? ?? '#d4a017',
    divider: json['divider'] as String? ?? '#e2e4ea',
    textMuted: json['disabled'] as String? ?? '#8b8da3',
    trustHigh: json['trustHigh'] as String? ?? '#2d5a9e',
    trustMedium: json['trustMedium'] as String? ?? '#2a9d5c',
    trustLow: json['trustLow'] as String? ?? '#d4a017',
  );

  Map<String, dynamic> toJson() => {
    'primary': primary,
    'primaryVariant': primaryVariant.isNotEmpty ? primaryVariant : _darken(primary),
    'secondary': secondary,
    'surface': surface,
    'surfaceVariant': surfaceVariant,
    'background': background,
    'onPrimary': onPrimary,
    'onSurface': onSurface,
    'onBackground': onBackground,
    'error': error,
    'success': success,
    'warning': warning,
    'divider': divider,
    'disabled': textMuted,
    'trustHigh': trustHigh,
    'trustMedium': trustMedium,
    'trustLow': trustLow,
  };

  String _darken(String hex) {
    // Simple darken for auto-generating primaryVariant
    if (!hex.startsWith('#') || hex.length < 7) return hex;
    final r = int.parse(hex.substring(1, 3), radix: 16);
    final g = int.parse(hex.substring(3, 5), radix: 16);
    final b = int.parse(hex.substring(5, 7), radix: 16);
    return '#${(r * 0.7).round().toRadixString(16).padLeft(2, '0')}'
        '${(g * 0.7).round().toRadixString(16).padLeft(2, '0')}'
        '${(b * 0.7).round().toRadixString(16).padLeft(2, '0')}';
  }
}

class ThemeTypography {
  final String displayFont;
  final String bodyFont;
  final String monoFont;

  const ThemeTypography({
    this.displayFont = 'Playfair Display',
    this.bodyFont = 'Source Sans 3',
    this.monoFont = 'JetBrains Mono',
  });

  factory ThemeTypography.fromJson(Map<String, dynamic> json) {
    final ff = json['fontFamily'] as Map<String, dynamic>? ?? {};
    return ThemeTypography(
      displayFont: ff['secondary'] as String? ?? ff['primary'] as String? ?? 'Playfair Display',
      bodyFont: ff['primary'] as String? ?? 'Source Sans 3',
      monoFont: ff['mono'] as String? ?? 'JetBrains Mono',
    );
  }

  Map<String, dynamic> toJson() => {
    'fontFamily': {
      'primary': bodyFont,
      'secondary': displayFont,
      'mono': monoFont,
    },
  };

  /// Google Fonts import URL
  String get googleFontsUrl {
    final fonts = <String>{displayFont, bodyFont, monoFont}
        .where((f) => f != 'system-ui')
        .map((f) => f.replaceAll(' ', '+'))
        .map((f) => 'family=$f:wght@400;500;600;700');
    return 'https://fonts.googleapis.com/css2?${fonts.join('&')}&display=swap';
  }
}

class ThemeTokens {
  final ThemeColors colors;
  final ThemeTypography typography;

  const ThemeTokens({required this.colors, this.typography = const ThemeTypography()});

  factory ThemeTokens.fromJson(Map<String, dynamic> json) => ThemeTokens(
    colors: ThemeColors.fromJson(json['colors'] as Map<String, dynamic>? ?? {}),
    typography: json['typography'] != null
        ? ThemeTypography.fromJson(json['typography'] as Map<String, dynamic>)
        : const ThemeTypography(),
  );

  Map<String, dynamic> toJson() => {
    'colors': colors.toJson(),
    'typography': typography.toJson(),
  };
}

// ============================================================
// COMPONENT STYLES
// ============================================================

class ThemeComponents {
  final String avatarShape;    // circle, rounded, square
  final String cardVariant;    // elevated, outlined, filled
  final String cardRadius;     // sm, md, lg, xl
  final String buttonRadius;   // sm, md, lg, full
  final String headerStyle;    // cover, minimal, centered
  final String sectionDivider; // line, space, none
  final String trustBadgeStyle; // minimal, detailed, compact

  const ThemeComponents({
    this.avatarShape = 'circle',
    this.cardVariant = 'outlined',
    this.cardRadius = 'md',
    this.buttonRadius = 'md',
    this.headerStyle = 'minimal',
    this.sectionDivider = 'line',
    this.trustBadgeStyle = 'detailed',
  });

  factory ThemeComponents.defaults() => const ThemeComponents();

  factory ThemeComponents.fromJson(Map<String, dynamic> json) => ThemeComponents(
    avatarShape: json['avatar']?['shape'] as String? ?? 'circle',
    cardVariant: json['card']?['variant'] as String? ?? 'outlined',
    cardRadius: json['card']?['borderRadius'] as String? ?? 'md',
    buttonRadius: json['button']?['borderRadius'] as String? ?? 'md',
    headerStyle: json['header']?['style'] as String? ?? 'minimal',
    sectionDivider: json['section']?['divider'] as String? ?? 'line',
    trustBadgeStyle: json['trustBadge']?['style'] as String? ?? 'detailed',
  );

  Map<String, dynamic> toJson() => {
    'avatar': {'shape': avatarShape},
    'card': {'variant': cardVariant, 'borderRadius': cardRadius},
    'button': {'borderRadius': buttonRadius},
    'header': {'style': headerStyle},
    'section': {'divider': sectionDivider},
    'trustBadge': {'style': trustBadgeStyle},
  };
}

class ThemeLayout {
  final String template;  // profile, storefront, etc.
  final String variant;   // minimal, creative, professional
  final String maxWidth;  // sm, md, lg, xl

  const ThemeLayout({
    this.template = 'profile',
    this.variant = 'minimal',
    this.maxWidth = 'lg',
  });

  factory ThemeLayout.defaults() => const ThemeLayout();

  factory ThemeLayout.fromJson(Map<String, dynamic> json) => ThemeLayout(
    template: json['template'] as String? ?? 'profile',
    variant: json['variant'] as String? ?? 'minimal',
    maxWidth: json['maxWidth'] as String? ?? 'lg',
  );

  Map<String, dynamic> toJson() => {
    'template': template,
    'variant': variant,
    'maxWidth': maxWidth,
  };
}

class DarkModeConfig {
  final bool enabled;
  final ThemeColors? colors;

  const DarkModeConfig({this.enabled = true, this.colors});

  factory DarkModeConfig.fromJson(Map<String, dynamic> json) => DarkModeConfig(
    enabled: json['enabled'] as bool? ?? true,
    colors: json['colors'] != null ? ThemeColors.fromJson(json['colors']) : null,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (colors != null) 'colors': colors!.toJson(),
  };
}

// ============================================================
// CSS GENERATOR — Theme JSON → CSS Variables
// ============================================================

class ThemeEngine {
  /// Generate complete CSS from a theme, including font imports
  static String generateCSS(GSiteTheme theme, {bool darkMode = false}) {
    final colors = theme.tokens.colors;
    final typo = theme.tokens.typography;
    final comp = theme.components;
    final avatarRadius = comp.avatarShape == 'circle' ? '50%'
        : comp.avatarShape == 'rounded' ? '12px' : '4px';
    final cardRadius = {'sm': '4px', 'md': '8px', 'lg': '12px', 'xl': '16px'}[comp.cardRadius] ?? '8px';
    final btnRadius = {'sm': '4px', 'md': '8px', 'lg': '12px', 'full': '9999px'}[comp.buttonRadius] ?? '8px';
    final sectionBorder = comp.sectionDivider == 'line' ? '2px solid ${_lighten(colors.primary)}' 
        : comp.sectionDivider == 'space' ? 'none' : 'none';
    final sectionMargin = comp.sectionDivider == 'space' ? '3rem' : '2.25rem';

    return '''
  <!-- Fonts -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="${typo.googleFontsUrl}" rel="stylesheet">
  <style>
    :root {
      /* Colors */
      --color-bg: ${colors.background};
      --color-surface: ${colors.surface};
      --color-surface-variant: ${colors.surfaceVariant.isNotEmpty ? colors.surfaceVariant : _lighten(colors.surface)};
      --color-text: ${colors.onSurface};
      --color-text-secondary: ${colors.textMuted.replaceAll('#8b8da3', '#4a4a65')};
      --color-text-muted: ${colors.textMuted};
      --color-accent: ${colors.primary};
      --color-accent-light: ${_lighten(colors.primary)};
      --color-accent-hover: ${colors.primaryVariant.isNotEmpty ? colors.primaryVariant : _darken(colors.primary)};
      --color-secondary: ${colors.secondary};
      --color-border: ${colors.divider};
      --color-border-light: ${_lighten(colors.divider)};
      --color-success: ${colors.success};
      --color-warning: ${colors.warning};
      --color-error: ${colors.error};
      --color-trust-high: ${colors.trustHigh};
      --color-trust-med: ${colors.trustMedium};
      --color-trust-low: ${colors.trustLow};
      --color-trust-new: ${colors.textMuted};

      /* Typography */
      --font-display: '${typo.displayFont}', Georgia, serif;
      --font-body: '${typo.bodyFont}', -apple-system, BlinkMacSystemFont, sans-serif;
      --font-mono: '${typo.monoFont}', 'Fira Code', monospace;

      /* Shapes */
      --radius-sm: 4px;
      --radius-md: 8px;
      --radius-lg: 12px;
      --radius-full: 9999px;
      --avatar-radius: $avatarRadius;
      --card-radius: $cardRadius;
      --btn-radius: $btnRadius;

      /* Shadows */
      --shadow-sm: 0 1px 3px rgba(0,0,0,0.05);
      --shadow-md: 0 4px 12px rgba(0,0,0,0.07);
      --shadow-lg: 0 8px 30px rgba(0,0,0,0.09);

      /* Layout */
      --sidebar-width: 290px;
      --content-max: 780px;

      /* Section */
      --section-border: $sectionBorder;
      --section-margin: $sectionMargin;
    }

    /* Component overrides from theme */
    .avatar-container { border-radius: var(--avatar-radius) !important; }
    .facet-card, .verification-item, .info-card { border-radius: var(--card-radius) !important; }
    .action-btn { border-radius: var(--btn-radius) !important; }
    .section { margin-bottom: var(--section-margin) !important; }
    .section-title { border-bottom: var(--section-border) !important; }
    ${comp.sectionDivider == 'space' ? '.section-title { padding-bottom: 0 !important; }' : ''}
  </style>''';
  }

  /// Lighten a hex color
  static String _lighten(String hex) {
    if (!hex.startsWith('#') || hex.length < 7) return '#f0f1f5';
    final r = int.parse(hex.substring(1, 3), radix: 16);
    final g = int.parse(hex.substring(3, 5), radix: 16);
    final b = int.parse(hex.substring(5, 7), radix: 16);
    final lr = (r + (255 - r) * 0.85).round().clamp(0, 255);
    final lg = (g + (255 - g) * 0.85).round().clamp(0, 255);
    final lb = (b + (255 - b) * 0.85).round().clamp(0, 255);
    return '#${lr.toRadixString(16).padLeft(2, '0')}'
        '${lg.toRadixString(16).padLeft(2, '0')}'
        '${lb.toRadixString(16).padLeft(2, '0')}';
  }

  static String _darken(String hex) {
    if (!hex.startsWith('#') || hex.length < 7) return '#1e3f73';
    final r = int.parse(hex.substring(1, 3), radix: 16);
    final g = int.parse(hex.substring(3, 5), radix: 16);
    final b = int.parse(hex.substring(5, 7), radix: 16);
    return '#${(r * 0.7).round().toRadixString(16).padLeft(2, '0')}'
        '${(g * 0.7).round().toRadixString(16).padLeft(2, '0')}'
        '${(b * 0.7).round().toRadixString(16).padLeft(2, '0')}';
  }
}

// ============================================================
// 8 PRESET THEMES
// ============================================================

class PresetThemes {
  static List<GSiteTheme> get all => [
    academic,
    midnight,
    coral,
    forest,
    lavender,
    brutalist,
    warm,
    ocean,
  ];

  static GSiteTheme get defaultTheme => academic;

  static GSiteTheme? byId(String id) {
    try {
      return all.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  // ---- 1. ACADEMIC (Default — AcademicPages inspired) ----
  static const academic = GSiteTheme(
    id: 'academic',
    name: 'Academic',
    description: 'Clean, professional layout inspired by academic pages. Perfect for researchers, developers, and professionals.',
    categories: ['professional', 'tech', 'academic'],
    tokens: ThemeTokens(
      colors: ThemeColors(
        primary: '#2d5a9e',
        secondary: '#6c757d',
        surface: '#ffffff',
        surfaceVariant: '#f8f9fa',
        background: '#fafaf8',
        onPrimary: '#ffffff',
        onSurface: '#1a1a2e',
        onBackground: '#1a1a2e',
        divider: '#e2e4ea',
        textMuted: '#8b8da3',
      ),
      typography: ThemeTypography(
        displayFont: 'Playfair Display',
        bodyFont: 'Source Sans 3',
        monoFont: 'JetBrains Mono',
      ),
    ),
    components: ThemeComponents(
      avatarShape: 'circle',
      cardVariant: 'outlined',
      cardRadius: 'md',
      buttonRadius: 'md',
      sectionDivider: 'line',
    ),
    layout: ThemeLayout(template: 'profile', variant: 'minimal'),
  );

  // ---- 2. MIDNIGHT — Dark, sleek, developer-focused ----
  static const midnight = GSiteTheme(
    id: 'midnight',
    name: 'Midnight',
    description: 'Dark mode by default. Sleek and modern, ideal for developers and creators.',
    categories: ['dark', 'tech', 'creative'],
    tokens: ThemeTokens(
      colors: ThemeColors(
        primary: '#60a5fa',
        secondary: '#a78bfa',
        surface: '#1e293b',
        surfaceVariant: '#334155',
        background: '#0f172a',
        onPrimary: '#0f172a',
        onSurface: '#e2e8f0',
        onBackground: '#e2e8f0',
        divider: '#334155',
        textMuted: '#94a3b8',
        success: '#34d399',
        warning: '#fbbf24',
        error: '#f87171',
        trustHigh: '#60a5fa',
        trustMedium: '#34d399',
        trustLow: '#fbbf24',
      ),
      typography: ThemeTypography(
        displayFont: 'JetBrains Mono',
        bodyFont: 'Source Sans 3',
        monoFont: 'JetBrains Mono',
      ),
    ),
    components: ThemeComponents(
      avatarShape: 'rounded',
      cardVariant: 'outlined',
      cardRadius: 'lg',
      buttonRadius: 'md',
      sectionDivider: 'space',
    ),
    layout: ThemeLayout(template: 'profile', variant: 'minimal'),
  );

  // ---- 3. CORAL — Warm, creative, portfolio-ready ----
  static const coral = GSiteTheme(
    id: 'coral',
    name: 'Coral Sunset',
    description: 'Warm coral tones with creative flair. Perfect for designers, artists, and freelancers.',
    categories: ['creative', 'warm', 'portfolio'],
    tokens: ThemeTokens(
      colors: ThemeColors(
        primary: '#e8614d',
        secondary: '#f4a261',
        surface: '#ffffff',
        surfaceVariant: '#fef7f4',
        background: '#fffaf8',
        onPrimary: '#ffffff',
        onSurface: '#2d1f1a',
        onBackground: '#2d1f1a',
        divider: '#f0ddd6',
        textMuted: '#a08478',
        success: '#4caf50',
        trustHigh: '#e8614d',
        trustMedium: '#4caf50',
      ),
      typography: ThemeTypography(
        displayFont: 'Playfair Display',
        bodyFont: 'Lato',
        monoFont: 'Source Code Pro',
      ),
    ),
    components: ThemeComponents(
      avatarShape: 'circle',
      cardVariant: 'elevated',
      cardRadius: 'xl',
      buttonRadius: 'full',
      sectionDivider: 'space',
    ),
    layout: ThemeLayout(template: 'profile', variant: 'creative'),
  );

  // ---- 4. FOREST — Earthy, calm, sustainability-focused ----
  static const forest = GSiteTheme(
    id: 'forest',
    name: 'Forest',
    description: 'Earthy greens and natural tones. Great for sustainability, wellness, and nature-focused identities.',
    categories: ['nature', 'wellness', 'calm'],
    tokens: ThemeTokens(
      colors: ThemeColors(
        primary: '#2d6a4f',
        secondary: '#95d5b2',
        surface: '#ffffff',
        surfaceVariant: '#f0faf4',
        background: '#f5faf7',
        onPrimary: '#ffffff',
        onSurface: '#1b2e22',
        onBackground: '#1b2e22',
        divider: '#d8e9df',
        textMuted: '#7a9987',
        success: '#40916c',
        trustHigh: '#2d6a4f',
        trustMedium: '#40916c',
      ),
      typography: ThemeTypography(
        displayFont: 'Merriweather',
        bodyFont: 'Lora',
        monoFont: 'JetBrains Mono',
      ),
    ),
    components: ThemeComponents(
      avatarShape: 'circle',
      cardVariant: 'outlined',
      cardRadius: 'lg',
      buttonRadius: 'lg',
      sectionDivider: 'line',
    ),
    layout: ThemeLayout(template: 'profile', variant: 'minimal'),
  );

  // ---- 5. LAVENDER — Soft, modern, approachable ----
  static const lavender = GSiteTheme(
    id: 'lavender',
    name: 'Lavender',
    description: 'Soft purple tones with a modern, approachable feel. Great for personal brands and communities.',
    categories: ['modern', 'soft', 'personal'],
    tokens: ThemeTokens(
      colors: ThemeColors(
        primary: '#7c3aed',
        secondary: '#a78bfa',
        surface: '#ffffff',
        surfaceVariant: '#faf5ff',
        background: '#faf8ff',
        onPrimary: '#ffffff',
        onSurface: '#1e1b2e',
        onBackground: '#1e1b2e',
        divider: '#e9e0f5',
        textMuted: '#9b8fb5',
        success: '#10b981',
        trustHigh: '#7c3aed',
        trustMedium: '#10b981',
      ),
      typography: ThemeTypography(
        displayFont: 'Poppins',
        bodyFont: 'Poppins',
        monoFont: 'Fira Code',
      ),
    ),
    components: ThemeComponents(
      avatarShape: 'rounded',
      cardVariant: 'elevated',
      cardRadius: 'xl',
      buttonRadius: 'full',
      sectionDivider: 'space',
    ),
    layout: ThemeLayout(template: 'profile', variant: 'creative'),
  );

  // ---- 6. BRUTALIST — Raw, bold, anti-design ----
  static const brutalist = GSiteTheme(
    id: 'brutalist',
    name: 'Brutalist',
    description: 'Raw, bold, and unapologetic. For those who want to stand out with an anti-design aesthetic.',
    categories: ['bold', 'artistic', 'experimental'],
    tokens: ThemeTokens(
      colors: ThemeColors(
        primary: '#000000',
        secondary: '#ff3366',
        surface: '#ffffff',
        surfaceVariant: '#f5f5f5',
        background: '#ffffff',
        onPrimary: '#ffffff',
        onSurface: '#000000',
        onBackground: '#000000',
        divider: '#000000',
        textMuted: '#666666',
        success: '#00cc66',
        trustHigh: '#000000',
        trustMedium: '#00cc66',
      ),
      typography: ThemeTypography(
        displayFont: 'Montserrat',
        bodyFont: 'Source Sans 3',
        monoFont: 'JetBrains Mono',
      ),
    ),
    components: ThemeComponents(
      avatarShape: 'square',
      cardVariant: 'outlined',
      cardRadius: 'sm',
      buttonRadius: 'sm',
      sectionDivider: 'line',
      trustBadgeStyle: 'minimal',
    ),
    layout: ThemeLayout(template: 'profile', variant: 'professional'),
  );

  // ---- 7. WARM — Cozy, inviting, business-friendly ----
  static const warm = GSiteTheme(
    id: 'warm',
    name: 'Warm Amber',
    description: 'Cozy amber tones perfect for cafés, restaurants, bakeries, and warm brands.',
    categories: ['warm', 'food', 'hospitality'],
    tokens: ThemeTokens(
      colors: ThemeColors(
        primary: '#b45309',
        secondary: '#d97706',
        surface: '#ffffff',
        surfaceVariant: '#fefce8',
        background: '#fffbf0',
        onPrimary: '#ffffff',
        onSurface: '#292524',
        onBackground: '#292524',
        divider: '#e8dcc8',
        textMuted: '#a18f7a',
        success: '#65a30d',
        trustHigh: '#b45309',
        trustMedium: '#65a30d',
      ),
      typography: ThemeTypography(
        displayFont: 'Playfair Display',
        bodyFont: 'Lato',
        monoFont: 'Source Code Pro',
      ),
    ),
    components: ThemeComponents(
      avatarShape: 'circle',
      cardVariant: 'elevated',
      cardRadius: 'lg',
      buttonRadius: 'lg',
      sectionDivider: 'line',
    ),
    layout: ThemeLayout(template: 'storefront', variant: 'minimal'),
  );

  // ---- 8. OCEAN — Fresh, clean, corporate-ready ----
  static const ocean = GSiteTheme(
    id: 'ocean',
    name: 'Ocean Blue',
    description: 'Clean, professional blues. Ideal for companies, organizations, and corporate identities.',
    categories: ['corporate', 'professional', 'clean'],
    tokens: ThemeTokens(
      colors: ThemeColors(
        primary: '#0369a1',
        secondary: '#0891b2',
        surface: '#ffffff',
        surfaceVariant: '#f0f9ff',
        background: '#f8fafc',
        onPrimary: '#ffffff',
        onSurface: '#0c1524',
        onBackground: '#0c1524',
        divider: '#d1e5f0',
        textMuted: '#6b8da6',
        success: '#059669',
        trustHigh: '#0369a1',
        trustMedium: '#059669',
      ),
      typography: ThemeTypography(
        displayFont: 'Montserrat',
        bodyFont: 'Open Sans',
        monoFont: 'Fira Code',
      ),
    ),
    components: ThemeComponents(
      avatarShape: 'circle',
      cardVariant: 'outlined',
      cardRadius: 'md',
      buttonRadius: 'md',
      sectionDivider: 'line',
      trustBadgeStyle: 'compact',
    ),
    layout: ThemeLayout(template: 'profile', variant: 'professional'),
  );
}
