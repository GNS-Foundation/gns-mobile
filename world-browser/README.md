# 🌐 GNS World Browser

**Browse Identities, Not Websites**

World Browser is the web interface for the GNS (Global Navigation & Settlement) network. It allows anyone to discover and explore verified identities, places, and businesses by their @handle.

```
┌─────────────────────────────────────────────────────────────────┐
│                      GNS ECOSYSTEM                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │   GLOBE      │   │    WORLD     │   │    GNS       │        │
│  │   CRUMBS     │   │   BROWSER    │   │   NODES      │        │
│  │   (Mobile)   │   │  ← YOU ARE   │   │  (Infra)     │        │
│  │              │   │     HERE     │   │              │        │
│  └──────────────┘   └──────────────┘   └──────────────┘        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Node.js 18+ 
- npm or yarn
- GNS Gateway API running (or use mock data)

### Installation

```bash
# Clone the repository
git clone https://github.com/gns-protocol/world-browser.git
cd world-browser

# Install dependencies
npm install

# Copy environment variables
cp .env.example .env.local

# Start development server
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to see the app.

## 📁 Project Structure

```
world-browser/
├── app/                      # Next.js 14 App Router
│   ├── page.tsx              # Homepage
│   ├── layout.tsx            # Root layout with header/footer
│   ├── globals.css           # Global styles + Tailwind
│   ├── not-found.tsx         # 404 page
│   ├── [handle]/             # Dynamic profile pages (/@caterve)
│   │   └── page.tsx
│   ├── entity/
│   │   └── [slug]/           # Dynamic entity pages (/entity/colosseum)
│   │       └── page.tsx
│   ├── search/               # Search results page
│   │   └── page.tsx
│   └── api/                  # Internal API routes
│       ├── profile/[handle]/
│       ├── entity/[slug]/
│       └── search/
│
├── components/
│   ├── layout/               # Header, Footer
│   ├── identity/             # IdentityCard
│   └── ui/                   # SearchBar, etc.
│
├── lib/
│   ├── types.ts              # TypeScript type definitions
│   └── api.ts                # API client + mock data
│
├── public/                   # Static assets
├── styles/                   # Additional styles
├── tailwind.config.js        # Tailwind configuration
├── next.config.js            # Next.js configuration
└── package.json
```

## 🎨 Key Features

### Profile Pages (`/@handle`)

Visit any identity by their @handle:
- `browser.gns.xyz/@caterve`
- `browser.gns.xyz/@alice`

Features:
- Identity card with avatar, name, bio
- Trust score and breadcrumb count
- Links and social profiles
- QR code for mobile app connection
- SEO-optimized metadata

### Entity Pages (`/entity/:slug`)

Browse places, businesses, and more:
- `browser.gns.xyz/entity/colosseum`
- `browser.gns.xyz/entity/da-enzo-al29`

Features:
- Entity details and images
- Verified visitor count
- Recent visitors list
- Claim CTA for business owners
- Check-in deep link

### Search (`/search`)

Discover identities and entities:
- Search by @handle
- Search by name or location
- Filter by type (people, places, businesses)
- Browse categories

## 🔗 URL Structure

| URL Pattern | Description | Example |
|-------------|-------------|---------|
| `/` | Homepage | `browser.gns.xyz` |
| `/@:handle` | Profile by handle | `browser.gns.xyz/@caterve` |
| `/:handle` | Profile (without @) | `browser.gns.xyz/caterve` |
| `/entity/:slug` | Entity page | `browser.gns.xyz/entity/colosseum` |
| `/search` | Search page | `browser.gns.xyz/search?q=rome` |

## 🛠️ Development

### Mock Data

In development mode, the app uses mock data when the Gateway API is unavailable. See `lib/api.ts` for mock data definitions.

### Environment Variables

```env
# Gateway API (required for production)
GATEWAY_API_URL=http://localhost:3001
NEXT_PUBLIC_API_URL=http://localhost:3001

# App URL
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

### Available Scripts

```bash
npm run dev      # Start development server
npm run build    # Build for production
npm run start    # Start production server
npm run lint     # Run ESLint
```

## 🚢 Deployment

### Railway

1. Connect your GitHub repository to Railway
2. Set environment variables:
   - `GATEWAY_API_URL=https://api.gns.xyz`
   - `NEXT_PUBLIC_API_URL=https://api.gns.xyz`
   - `NEXT_PUBLIC_APP_URL=https://browser.gns.xyz`
3. Deploy!

Railway will automatically detect Next.js and configure the build.

### Custom Domain

Configure `browser.gns.xyz` to point to your Railway deployment.

## 🔌 Integration with Globe Crumbs

World Browser integrates with the Globe Crumbs mobile app via deep links:

| Action | Deep Link |
|--------|-----------|
| Open profile | `globecrumbs://profile/:publicKey` |
| Claim entity | `globecrumbs://claim/:slug` |
| Check in | `globecrumbs://checkin/:slug` |

## 📊 API Endpoints (Internal)

These routes forward requests to the Gateway API:

| Endpoint | Description |
|----------|-------------|
| `GET /api/profile/:handle` | Get identity by handle |
| `GET /api/entity/:slug` | Get entity by slug |
| `GET /api/search?q=...` | Search identities/entities |

## 🎯 Roadmap

### Phase 1 (Current)
- [x] Profile pages
- [x] Entity pages
- [x] Search functionality
- [x] Responsive design
- [ ] Gateway API integration

### Phase 2
- [ ] Real-time WebSocket updates
- [ ] Map visualizations
- [ ] Breadcrumb history view
- [ ] Business dashboard

### Phase 3
- [ ] GNS Token wallet integration
- [ ] Payment history
- [ ] Entity verification flow
- [ ] Analytics dashboard

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## 📄 License

MIT License - see LICENSE file for details.

---

**Part of the GNS Ecosystem** 🍞

- [Globe Crumbs](https://apps.apple.com/app/globe-crumbs) - Mobile app
- [GNS Protocol](https://gns.xyz) - Main website
- [Documentation](https://docs.gns.xyz) - Developer docs
