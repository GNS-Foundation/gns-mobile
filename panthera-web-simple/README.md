# GNS-CMS (Content Management System)

> The visual layer for GNS - Themes, Media, and gSite rendering

## Overview

GNS-CMS is the content management infrastructure that powers gSite rendering. Unlike traditional CMS platforms (Wix, WordPress), GNS-CMS:

- **Identity = Public Key** (not domain names)
- **Portable JSON** (not platform-locked databases)
- **Constrained Themes** (secure by design)
- **Universal Rendering** (same theme works on Web, Mobile, Desktop)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        GNS-CMS                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  schemas/                                                   │
│  └── theme.schema.json      JSON Schema for themes          │
│                                                             │
│  migrations/                                                │
│  ├── 004_cms_themes.sql     Database tables                 │
│  └── 005_seed_themes.sql    Default themes                  │
│                                                             │
│  api/                                                       │
│  ├── cms.ts                 API routes                      │
│  └── theme-renderer.ts      Universal renderer              │
│                                                             │
│  themes/default/                                            │
│  ├── profile-minimal.json                                   │
│  ├── profile-creative.json                                  │
│  ├── profile-professional.json                              │
│  ├── storefront-modern.json                                 │
│  ├── storefront-warm.json                                   │
│  └── storefront-elegant.json                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Run Migrations (Supabase)

```sql
-- Run in Supabase SQL Editor
-- First: 004_cms_themes.sql (creates tables)
-- Then: 005_seed_themes.sql (seeds default themes)
```

### 2. Add API Routes (Railway)

```typescript
// src/index.ts
import cmsRouter from './api/cms';

app.use('/cms', cmsRouter);
```

### 3. Test

```bash
# List themes
curl https://your-api.up.railway.app/cms/themes

# Get specific theme
curl https://your-api.up.railway.app/cms/themes/profile-creative

# Get theme for a gSite
curl https://your-api.up.railway.app/cms/gsite/@camiloayerbe/theme
```

## API Endpoints

### Themes

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/cms/themes` | List all themes (with filters) |
| GET | `/cms/themes/:id` | Get theme by ID |
| POST | `/cms/themes` | Create theme (marketplace) |
| POST | `/cms/themes/:id/validate` | Validate theme |
| POST | `/cms/themes/:id/rate` | Rate a theme |
| GET | `/cms/themes/:id/ratings` | Get theme ratings |

### gSite Theming

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/cms/gsite/:id/theme` | Get applied theme |
| PUT | `/cms/gsite/:id/theme` | Apply theme + overrides |

## Theme Schema

Themes are defined in JSON with these sections:

```json
{
  "id": "profile-creative",
  "name": "Creative",
  "version": "1.0.0",
  "entityTypes": ["Person"],
  "tokens": {
    "colors": { ... },
    "typography": { ... },
    "spacing": { ... },
    "borders": { ... },
    "shadows": { ... }
  },
  "components": {
    "card": { "variant": "elevated", ... },
    "button": { "variant": "filled", ... },
    "avatar": { "shape": "circle", ... }
  },
  "layout": {
    "template": "profile",
    "sections": ["header", "actions", "about", "links"]
  },
  "darkMode": {
    "enabled": true,
    "colors": { ... }
  }
}
```

## Default Themes (6)

### Person
- **profile-minimal** - Clean, simple design
- **profile-creative** - Bold, artistic layout
- **profile-professional** - Business-focused

### Business
- **storefront-modern** - Contemporary, tech-friendly
- **storefront-warm** - Cozy for cafes/restaurants
- **storefront-elegant** - Luxury/fine dining

## Theme Renderer

The universal renderer generates platform-specific styles:

```typescript
import { generateCSSVariables, generateFlutterTheme } from './theme-renderer';

// For Web
const css = generateCSSVariables(theme, isDarkMode);
// Outputs: :root { --color-primary: #E94560; ... }

// For Flutter
const dart = generateFlutterTheme(theme, isDarkMode);
// Outputs: ThemeData with ColorScheme, TextTheme, etc.
```

## Database Tables

| Table | Purpose |
|-------|---------|
| `themes` | Theme definitions |
| `theme_purchases` | Marketplace transactions |
| `theme_ratings` | Reviews & ratings |
| `gsite_themes` | gSite → Theme assignments |
| `media` | Uploaded images/files |

## Owner Overrides

gSite owners can customize themes within constraints:

```json
{
  "themeId": "profile-creative",
  "overrides": {
    "colors": {
      "primary": "#2E7D32",
      "secondary": "#1B5E20"
    }
  }
}
```

**Constraints enforced:**
- Colors must pass WCAG 2.1 AA contrast
- Fonts must be from allowed list
- No arbitrary CSS/code execution

## Security

1. **No Code Execution** - Themes are pure data
2. **No External Resources** - All fonts pre-loaded
3. **Validated Inputs** - JSON Schema enforcement
4. **Contrast Checking** - Accessibility guaranteed

## Revenue Model

| Tier | Price | Creator Split |
|------|-------|---------------|
| Free | $0 | N/A |
| Standard | $5-25 | 70% / 30% |
| Premium | $25-100 | 80% / 20% |

## Next Steps

1. Run migrations in Supabase
2. Add `cms.ts` to Railway backend
3. Update web renderer to fetch themes
4. Build Flutter theme consumer
5. Launch Theme Marketplace

---

**GNS-CMS: Where Identity Meets Design** 🎨
