# GCRUMBS — Claude Code Context

## What This Is

GCRUMBS is a decentralized identity and encrypted messaging app built on the GNS Protocol stack. Flutter/Dart, targeting iOS first then Android. The app has 5 tabs: Map / Chat / Hive / Digest / Profile.

Company: ULISSY s.r.l. (Rome). Foundation: GNS Foundation (Zug, Switzerland). Founder: Camilo Ayerbe Posada.

## Current State (April 2026)

The app has production-grade E2E encryption, WebRTC voice/video calls with CallKit, GNS identity, and a working compose area. What's missing is the "last mile" — the features users expect from day one in a messaging app.

## Sprint 1 Blockers — Must Fix Before App Store

These are the 5 launch blockers. Each one causes immediate user churn if missing.

### 1. Image & Photo Sending

**Current state:** `ComposeArea` has `onAttachmentPressed` and `onCameraPressed` callbacks that exist but have no handler wired.

**What to build:**
- Image picker (camera + gallery) wired to ComposeArea callbacks
- Client-side image compression (max 1200px, JPEG 85%) before encryption
- Encrypt image blob using same X25519+HKDF scheme as text messages
- Upload encrypted blob to Railway `/messages/media` endpoint (needs to be created)
- `MessageBubble`: image preview with tap-to-expand full screen viewer
- File picker (PDF, DOCX, XLSX) via `file_picker` package
- `FileBubble` widget: file icon, name, size, download progress
- Backend: `/messages/media` upload + signed URL generation for download

**Media message payload type:**
```
payload_type: gns/attachment.image | gns/attachment.audio | gns/attachment.document
Fields: url, mime_type, size_bytes, duration_ms?, thumbnail_b64?, encryption_key, iv
```

**Encryption:** Per-file AES-256 key, encrypted with recipient X25519 key. The file itself is AES-GCM encrypted. The key+IV travel inside the GNS envelope (which is itself E2E encrypted).

### 2. Push Notifications (Messages)

**Current state:** CallKit VoIP push works for incoming calls. No push for messages. App must be open to receive messages.

**What to build:**
- APNs setup for iOS (non-VoIP notification certificate) — `lib/core/notifications/apns_token_service.dart` already exists
- Firebase Cloud Messaging setup for Android
- Backend: store FCM/APNs token per public key in Supabase
- Backend: send push notification on message relay (only when WebSocket is disconnected)
- Flutter: handle notification tap → navigate to correct conversation
- Notification content: sender handle + "New message" (NO plaintext in push — E2E integrity)

**Push payload structure (never contains message content):**
```
title: "New message"
body: "Tap to view"
data.conversationId: thread ID
data.senderPk: sender public key
data.messageType: "text" | "media" | "call"
```

### 3. Read Receipts (✓✓ blue)

**Current state:** `MessageStatus` enum exists (sending/sent/delivered/read). Status ticks render in UI. Backend doesn't emit delivery/read events.

**What to build:**
- Backend: emit `message_delivered` WebSocket event when message is relayed to recipient
- Backend: emit `message_read` WebSocket event when recipient opens conversation
- Flutter: update `MessageStatus` on delivery/read events via WebSocket
- `ConversationScreen`: double tick (✓✓) turns blue on read confirmation

**Protocol:**
```
sent       → message accepted by backend (200 response)     → ✓
delivered  → recipient WebSocket receives envelope           → ✓✓ grey
read       → recipient opens conversation containing msg     → ✓✓ blue
```

### 4. In-Thread Message Search

**Current state:** Not started.

**What to build:**
- SearchBar widget in `ConversationScreen` (animated, same style as UnifiedInbox)
- SQLite full-text search on decrypted message content (FTS5 extension)
- Results highlight matching text in bubble, tap jumps to message in list
- Search scope: current conversation only (global search in Sprint 2)

### 5. Voice Messages (Sprint 2 but easy win)

**Current state:** Mic button visual exists in ComposeArea, no recording logic.

**What to build:**
- Press-and-hold mic button activates recording via `flutter_sound`
- Waveform visualization during recording
- Send: encrypt audio blob + duration as `gns/attachment.audio` payload
- `VoiceBubble`: waveform scrubber, play/pause, duration, playback speed

## Sprint 1 Acceptance Criteria

Sprint 1 is COMPLETE when: a user can start a new conversation, send a text message, receive a push notification when the app is closed, send a photo from camera or gallery, share a PDF, see read receipts turn blue, and search past messages in a thread.

## Architecture

### E2E Encryption (DO NOT MODIFY)

Every message follows this path:

1. **Sender:** compose plaintext → fetch recipient X25519 public key → generate ephemeral X25519 keypair → ECDH shared secret → HKDF with info string `"gns-envelope-v1:" + ephPub(32) + recipientPub(32)` → AES-GCM encrypt payload → sign with sender Ed25519 key → null-excluded canonical JSON envelope.

2. **Backend (Railway):** relay encrypted envelope. Cannot decrypt. WebSocket delivery if online, queue if offline.

3. **Recipient:** ECDH derive shared secret → HKDF derive AES key → decrypt → verify Ed25519 signature → render.

**CRITICAL:** The HKDF info string MUST be `"gns-envelope-v1:" + ephPub(32 bytes) + recipientPub(32 bytes)`. Mismatch between platforms is the most common E2E crypto bug.

### GNS Identity (DO NOT MODIFY)

- Identity = Ed25519 public key, generated locally, never transmitted
- @handles: human-readable aliases registered against public key in Supabase
- Trust tiers: Seedling → Explorer → Navigator → Trailblazer (earned via Proof-of-Trajectory)
- X25519 encryption key: separate from Ed25519 identity key
- SecureStorage: `first_unlock` + `synchronizable: true` for iCloud Keychain sync

### Backend

- Railway service: `gns-backend` (TypeScript, `src/api/`)
- Supabase: GNS-NETWORK project `nsthmevgpkskmgmubdju`
- WebSocket: real-time message relay, typing indicators, presence
- Email: Mailgun EU, domain `gcrumbs.com`
- Railway auto-deploys on `git push origin main`

### Backend Endpoints

```
POST /messages              — relay encrypted envelope
GET  /messages/:pk          — fetch pending messages
GET  /handles/pk/:pk        — resolve handle → public key
GET  /handles/resolve/:handle — resolve handle → public key
POST /calls/turn-credentials — WebRTC TURN credentials
POST /records               — publish GNS record
GET  /records/:pk           — get identity record
```

### Local Storage

- SQLite via `sqflite` for breadcrumbs, messages, contacts
- SecureStorage for keypairs (iCloud Keychain sync)
- Chain storage: `lib/core/chain/chain_storage.dart`
- Message storage: `lib/core/comm/message_storage.dart` (if exists) or inline in communication_service

## Key Files

### Core Services (lib/core/)
```
comm/communication_service.dart  — message send/receive, WebSocket
comm/gns_envelope.dart           — E2E encryption envelope
comm/relay_channel.dart          — WebSocket relay connection
comm/payload_types.dart          — message type definitions
crypto/secure_storage.dart       — keypair storage
crypto/comm_crypto_service.dart  — X25519/HKDF crypto
chain/breadcrumb_engine.dart     — trajectory breadcrumb collection
chain/chain_storage.dart         — SQLite breadcrumb storage
gns/gns_api_client.dart          — backend API client
gns/identity_wallet.dart         — identity management
notifications/apns_token_service.dart — push token handling
profile/profile_service.dart     — profile management
theme/theme_service.dart         — app theming
hive/                            — Hive worker service
sync/                            — sync service
trajectory/                      — trajectory tracking
branding/                        — app branding
```

### UI (lib/ui/)
```
messages/compose_area.dart           — compose bar with send/mic/attachment
messages/conversation_screen.dart    — main chat screen
messages/message_bubble.dart         — message rendering
messages/thread_list_screen.dart     — conversation list
messages/new_conversation_screen.dart — start new chat
messages/unified_inbox_screen.dart   — unified inbox (chat/DIX/email)
messages/email_list_screen.dart      — email gateway
home/home_tab.dart                   — home screen
globe/globe_tab.dart                 — map tab
dix/dix_timeline_screen.dart         — public feed
dix/dix_compose_screen.dart          — compose public post
settings/settings_tab.dart           — settings
hive/                                — hive worker UI
trajectory/                          — trajectory visualization
profile/profile_editor_screen.dart   — edit profile
screens/debug_screen.dart            — debug tools
screens/browser_pairing_screen.dart  — desktop pairing
widgets/identity_card.dart           — identity display card
widgets/gep_address_row.dart         — GEP address display
```

### Entry Points
```
main.dart                    — app initialization
navigation/main_navigation.dart — tab navigation (5 tabs)
```

## Packages (pubspec.yaml)

Key dependencies to be aware of:
- `flutter_webrtc` — WebRTC calls
- `flutter_callkit_incoming` — iOS CallKit
- `sqflite` — local SQLite
- `flutter_secure_storage` — secure keypair storage
- `cryptography` / `pointycastle` — crypto operations
- `h3_flutter` — H3 hex grid
- `flutter_map` — map rendering
- `web_socket_channel` — WebSocket connection

Packages to ADD for Sprint 1:
- `image_picker` — camera/gallery photo selection
- `file_picker` — document selection
- `firebase_messaging` — FCM push (Android)
- `flutter_image_compress` — client-side image compression
- `flutter_sound` — voice message recording (Sprint 2)

## Canonical Patterns

### JSON Serialization
Alphabetically sorted keys, null values excluded, then SHA256 + Ed25519 sign.

### WebSocket Messages
Typed messages with `type` field: `message`, `typing`, `presence`, `call_offer`, `call_answer`, `call_ice`, `call_hangup`, `message_delivered`, `message_read`.

### Error Handling
All API calls wrapped in try/catch. Offline-first: queue locally, sync when connected.

### System Bots
- `@echo` — test bot
- `@hai` — AI assistant (Hive inference)
- System bots store X25519 keys in Railway process memory. Key lookup must fall back to `/handles/pk/<publicKey>`.

## DO NOT TOUCH

These components are working and audited. Do not modify without explicit instruction:

- E2E encryption (gns_envelope.dart, comm_crypto_service.dart)
- WebRTC call infrastructure (call_service.dart, callkit_service.dart)
- GNS identity/keypair generation (identity_keypair.dart, identity_wallet.dart)
- Breadcrumb engine (breadcrumb_engine.dart)
- Secure storage (secure_storage.dart)

## Build & Run

```bash
cd ~/gns_browser
flutter pub get
flutter run          # debug
flutter build ios    # release iOS
flutter analyze      # lint check
```

## Git

- Repo: github.com/GNS-Foundation/gns-mobile
- Branch: main
- Railway auto-deploys backend on push to gns-backend repo
- This repo is Flutter only — backend is separate

## Related Repos

- `GNS-Foundation/geiant` — GEIANT monorepo (MCP servers, perception, agentcore)
- `GNS-Foundation/gns-backend` — Railway backend (TypeScript)
- `GNS-Foundation/gep-core` — GeoEpoch Protocol
- `GNS-Foundation/trip-protocol` — IETF draft
- `GNS-Foundation/mobydb-benchmark` — MobyDB benchmark
