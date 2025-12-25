// ===========================================
// GNS-CMS: UNIVERSAL THEME RENDERER
// ===========================================
// This utility transforms theme JSON into platform-specific styles
// Use: Web (CSS variables), Flutter (ThemeData), React Native, etc.
// ===========================================

export interface ThemeTokens {
  colors: {
    primary: string;
    primaryVariant: string;
    secondary: string;
    secondaryVariant: string;
    surface: string;
    surfaceVariant: string;
    background: string;
    onPrimary: string;
    onSecondary: string;
    onSurface: string;
    onBackground: string;
    error: string;
    success: string;
    warning: string;
    info: string;
    divider: string;
    disabled: string;
    shadow: string;
    trustLow: string;
    trustMedium: string;
    trustHigh: string;
    trustVerified: string;
  };
  typography: {
    fontFamily: {
      primary: string;
      secondary: string;
      mono: string;
    };
    fontSize: Record<string, number>;
    fontWeight: Record<string, number>;
    lineHeight: Record<string, number>;
  };
  spacing: Record<string, number>;
  borders: {
    radius: Record<string, number>;
    width: Record<string, number>;
  };
  shadows: Record<string, string>;
}

export interface ThemeComponents {
  card: {
    variant: 'elevated' | 'outlined' | 'filled';
    shadow: string;
    borderRadius: string;
  };
  button: {
    variant: 'filled' | 'outlined' | 'text' | 'icon';
    borderRadius: string;
    size: string;
  };
  avatar: {
    shape: 'circle' | 'rounded' | 'square';
    border: boolean;
    borderColor?: string;
  };
  trustBadge: {
    style: 'minimal' | 'detailed' | 'compact';
    showBreadcrumbs: boolean;
    showVerifications: boolean;
  };
  actionBar: {
    position: 'inline' | 'fixed-bottom' | 'floating';
    style: 'icons' | 'labels' | 'both';
  };
  header: {
    style: 'cover' | 'minimal' | 'centered';
    coverHeight: number;
    avatarPosition: 'left' | 'center' | 'overlap';
  };
  section: {
    divider: 'line' | 'space' | 'none';
    titleStyle: 'uppercase' | 'normal' | 'bold';
  };
}

export interface ThemeLayout {
  template: string;
  variant: string;
  sections: string[];
  gridColumns: {
    mobile: number;
    tablet: number;
    desktop: number;
  };
  maxWidth: string;
}

export interface Theme {
  id: string;
  name: string;
  tokens: ThemeTokens;
  components: ThemeComponents;
  layout: ThemeLayout;
  darkMode?: {
    enabled: boolean;
    colors: Partial<ThemeTokens['colors']>;
  };
}

// ===========================================
// CSS VARIABLE GENERATOR (Web)
// ===========================================

export function generateCSSVariables(theme: Theme, isDark = false): string {
  const tokens = theme.tokens;
  const colors = isDark && theme.darkMode?.enabled 
    ? { ...tokens.colors, ...theme.darkMode.colors }
    : tokens.colors;

  const lines: string[] = [':root {'];

  // Colors
  Object.entries(colors).forEach(([key, value]) => {
    const cssKey = key.replace(/([A-Z])/g, '-$1').toLowerCase();
    lines.push(`  --color-${cssKey}: ${value};`);
  });

  // Typography
  const { fontFamily, fontSize, fontWeight, lineHeight } = tokens.typography;
  lines.push(`  --font-primary: '${fontFamily.primary}', system-ui, sans-serif;`);
  lines.push(`  --font-secondary: '${fontFamily.secondary}', system-ui, sans-serif;`);
  lines.push(`  --font-mono: '${fontFamily.mono}', monospace;`);

  Object.entries(fontSize).forEach(([key, value]) => {
    lines.push(`  --text-${key}: ${value}px;`);
  });

  Object.entries(fontWeight).forEach(([key, value]) => {
    lines.push(`  --font-${key}: ${value};`);
  });

  Object.entries(lineHeight).forEach(([key, value]) => {
    lines.push(`  --leading-${key}: ${value};`);
  });

  // Spacing
  Object.entries(tokens.spacing).forEach(([key, value]) => {
    lines.push(`  --space-${key}: ${value}px;`);
  });

  // Borders
  Object.entries(tokens.borders.radius).forEach(([key, value]) => {
    lines.push(`  --radius-${key}: ${value === 9999 ? '9999px' : `${value}px`};`);
  });

  Object.entries(tokens.borders.width).forEach(([key, value]) => {
    lines.push(`  --border-${key}: ${value}px;`);
  });

  // Shadows
  Object.entries(tokens.shadows).forEach(([key, value]) => {
    lines.push(`  --shadow-${key}: ${value};`);
  });

  // Component-specific
  const { components } = theme;
  lines.push(`  --card-radius: var(--radius-${components.card.borderRadius});`);
  lines.push(`  --card-shadow: var(--shadow-${components.card.shadow});`);
  lines.push(`  --button-radius: var(--radius-${components.button.borderRadius});`);
  lines.push(`  --header-cover-height: ${components.header.coverHeight}px;`);

  // Layout
  lines.push(`  --max-width-sm: 640px;`);
  lines.push(`  --max-width-md: 768px;`);
  lines.push(`  --max-width-lg: 1024px;`);
  lines.push(`  --max-width-xl: 1280px;`);
  lines.push(`  --content-max-width: var(--max-width-${theme.layout.maxWidth});`);

  lines.push('}');

  return lines.join('\n');
}

// ===========================================
// FLUTTER THEME GENERATOR
// ===========================================

export function generateFlutterTheme(theme: Theme, isDark = false): string {
  const tokens = theme.tokens;
  const colors = isDark && theme.darkMode?.enabled 
    ? { ...tokens.colors, ...theme.darkMode.colors }
    : tokens.colors;

  const hexToFlutter = (hex: string): string => {
    if (hex.startsWith('rgba')) {
      // Parse rgba(r,g,b,a) format
      const match = hex.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([0-9.]+))?\)/);
      if (match) {
        const r = parseInt(match[1]);
        const g = parseInt(match[2]);
        const b = parseInt(match[3]);
        const a = match[4] ? parseFloat(match[4]) : 1;
        return `Color.fromRGBO(${r}, ${g}, ${b}, ${a})`;
      }
    }
    // Parse hex format
    const cleanHex = hex.replace('#', '');
    return `Color(0xFF${cleanHex.toUpperCase()})`;
  };

  return `
// Generated by GNS-CMS Theme Renderer
// Theme: ${theme.id}

import 'package:flutter/material.dart';

class ${theme.id.split('-').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('')}Theme {
  static ThemeData get ${isDark ? 'dark' : 'light'}Theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.${isDark ? 'dark' : 'light'},
      colorScheme: ColorScheme(
        brightness: Brightness.${isDark ? 'dark' : 'light'},
        primary: ${hexToFlutter(colors.primary)},
        onPrimary: ${hexToFlutter(colors.onPrimary)},
        secondary: ${hexToFlutter(colors.secondary)},
        onSecondary: ${hexToFlutter(colors.onSecondary)},
        error: ${hexToFlutter(colors.error)},
        onError: Colors.white,
        background: ${hexToFlutter(colors.background)},
        onBackground: ${hexToFlutter(colors.onBackground)},
        surface: ${hexToFlutter(colors.surface)},
        onSurface: ${hexToFlutter(colors.onSurface)},
      ),
      fontFamily: '${tokens.typography.fontFamily.primary}',
      textTheme: TextTheme(
        displayLarge: TextStyle(fontSize: ${tokens.typography.fontSize['5xl']}, fontWeight: FontWeight.w${tokens.typography.fontWeight.bold}),
        displayMedium: TextStyle(fontSize: ${tokens.typography.fontSize['4xl']}, fontWeight: FontWeight.w${tokens.typography.fontWeight.bold}),
        displaySmall: TextStyle(fontSize: ${tokens.typography.fontSize['3xl']}, fontWeight: FontWeight.w${tokens.typography.fontWeight.semibold}),
        headlineLarge: TextStyle(fontSize: ${tokens.typography.fontSize['2xl']}, fontWeight: FontWeight.w${tokens.typography.fontWeight.semibold}),
        headlineMedium: TextStyle(fontSize: ${tokens.typography.fontSize.xl}, fontWeight: FontWeight.w${tokens.typography.fontWeight.semibold}),
        headlineSmall: TextStyle(fontSize: ${tokens.typography.fontSize.lg}, fontWeight: FontWeight.w${tokens.typography.fontWeight.medium}),
        titleLarge: TextStyle(fontSize: ${tokens.typography.fontSize.lg}, fontWeight: FontWeight.w${tokens.typography.fontWeight.semibold}),
        titleMedium: TextStyle(fontSize: ${tokens.typography.fontSize.base}, fontWeight: FontWeight.w${tokens.typography.fontWeight.medium}),
        titleSmall: TextStyle(fontSize: ${tokens.typography.fontSize.sm}, fontWeight: FontWeight.w${tokens.typography.fontWeight.medium}),
        bodyLarge: TextStyle(fontSize: ${tokens.typography.fontSize.base}),
        bodyMedium: TextStyle(fontSize: ${tokens.typography.fontSize.sm}),
        bodySmall: TextStyle(fontSize: ${tokens.typography.fontSize.xs}),
        labelLarge: TextStyle(fontSize: ${tokens.typography.fontSize.sm}, fontWeight: FontWeight.w${tokens.typography.fontWeight.medium}),
        labelMedium: TextStyle(fontSize: ${tokens.typography.fontSize.xs}, fontWeight: FontWeight.w${tokens.typography.fontWeight.medium}),
        labelSmall: TextStyle(fontSize: ${tokens.typography.fontSize.xs}),
      ),
      cardTheme: CardTheme(
        elevation: ${theme.components.card.shadow === 'none' ? 0 : theme.components.card.shadow === 'sm' ? 1 : theme.components.card.shadow === 'md' ? 4 : 8},
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(${tokens.borders.radius[theme.components.card.borderRadius] || 8}),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(${tokens.borders.radius[theme.components.button.borderRadius] || 8}),
          ),
        ),
      ),
      dividerColor: ${hexToFlutter(colors.divider)},
    );
  }
}
`;
}

// ===========================================
// TRUST SCORE COLOR
// ===========================================

export function getTrustColor(score: number, colors: ThemeTokens['colors']): string {
  if (score <= 25) return colors.trustLow;
  if (score <= 50) return colors.trustMedium;
  if (score <= 75) return colors.trustHigh;
  return colors.trustVerified;
}

// ===========================================
// COMPONENT CLASS GENERATOR
// ===========================================

export function generateComponentClasses(theme: Theme): Record<string, string> {
  const { components } = theme;

  return {
    // Card variants
    card: `
      background: var(--color-surface);
      border-radius: var(--card-radius);
      ${components.card.variant === 'elevated' ? 'box-shadow: var(--card-shadow);' : ''}
      ${components.card.variant === 'outlined' ? 'border: var(--border-thin) solid var(--color-divider);' : ''}
    `.trim(),

    // Button variants
    buttonPrimary: `
      background: var(--color-primary);
      color: var(--color-on-primary);
      border-radius: var(--button-radius);
      font-weight: var(--font-medium);
      padding: var(--space-3) var(--space-6);
    `.trim(),

    buttonSecondary: `
      background: transparent;
      color: var(--color-primary);
      border: var(--border-thin) solid var(--color-primary);
      border-radius: var(--button-radius);
      font-weight: var(--font-medium);
      padding: var(--space-3) var(--space-6);
    `.trim(),

    // Avatar
    avatar: `
      ${components.avatar.shape === 'circle' ? 'border-radius: 50%;' : ''}
      ${components.avatar.shape === 'rounded' ? 'border-radius: var(--radius-lg);' : ''}
      ${components.avatar.shape === 'square' ? 'border-radius: var(--radius-sm);' : ''}
      ${components.avatar.border ? `border: 3px solid var(--color-${components.avatar.borderColor || 'surface'});` : ''}
    `.trim(),

    // Trust badge
    trustBadge: `
      display: flex;
      align-items: center;
      gap: var(--space-2);
      font-size: var(--text-sm);
    `.trim(),

    // Section header
    sectionTitle: `
      font-family: var(--font-secondary);
      font-size: var(--text-sm);
      font-weight: var(--font-semibold);
      color: var(--color-on-surface);
      ${components.section.titleStyle === 'uppercase' ? 'text-transform: uppercase; letter-spacing: 0.05em;' : ''}
      margin-bottom: var(--space-4);
    `.trim(),

    // Header
    header: `
      ${components.header.style === 'cover' ? `
        position: relative;
        .cover-image {
          height: var(--header-cover-height);
          background-size: cover;
          background-position: center;
        }
      ` : ''}
    `.trim(),
  };
}

// ===========================================
// EXPORT
// ===========================================

export default {
  generateCSSVariables,
  generateFlutterTheme,
  getTrustColor,
  generateComponentClasses,
};
