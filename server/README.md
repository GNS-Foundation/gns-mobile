# 🌐 GNS Node

**Identity Resolution & Relay Network**

GNS Node is the server-side infrastructure for the GNS Network. It enables GNS Browser identities to discover and communicate with each other.

## Core Principle

> **Relays are dumb infrastructure, not identity authorities.**  
> Your identity remains your keypair. Your trust remains your breadcrumb chain.  
> Relays simply help phones find each other in a world of NATs and firewalls.

## Features

- **Identity Resolution**: Query by public key or @handle
- **Handle Registry**: Claim @usernames backed by Proof-of-Trajectory
- **Epoch Publishing**: Commit trajectory proofs to the network
- **Message Relay**: Forward encrypted payloads between identities
- **Node Gossip**: Sync data with peer nodes

## Quick Start

### Prerequisites

- Node.js 20+
- Supabase project (for PostgreSQL)

### Setup

1. **Clone and install**
```bash
cd gns-node
npm install
```

2. **Configure environment**
```bash
cp .env.example .env
# Edit .env with your Supabase credentials
```

3. **Run database migrations**
   - Go to Supabase SQL Editor
   - Run `gns_supabase_schema.sql`

4. **Start development server**
```bash
npm run dev
```

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SUPABASE_URL` | Supabase project URL | Yes |
| `SUPABASE_SERVICE_KEY` | Service role key (not anon!) | Yes |
| `PORT` | HTTP port (default: 3000) | No |
| `NODE_ID` | Unique identifier for this node | No |
| `PEER_NODES` | Comma-separated peer URLs | No |

## API Endpoints

### Records

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/records/:pk` | Resolve identity by public key |
| `PUT` | `/records/:pk` | Publish/update GNS Record |
| `DELETE` | `/records/:pk` | Remove record (requires signature) |

### Aliases

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/aliases/:handle` | Resolve @handle → PK_root |
| `GET` | `/aliases?check=:handle` | Check handle availability |
| `PUT` | `/aliases/:handle` | Claim handle (requires PoT) |
| `POST` | `/aliases/:handle/reserve` | Reserve handle for 30 days |

### Epochs

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/epochs/:pk` | List all epochs for identity |
| `GET` | `/epochs/:pk/:index` | Get specific epoch |
| `PUT` | `/epochs/:pk/:index` | Publish epoch commitment |

### Messages

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/messages/:to_pk` | Send encrypted message |
| `GET` | `/messages/inbox` | Fetch queued messages |
| `DELETE` | `/messages/:id` | Acknowledge receipt |

### Sync (Node-to-Node)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/sync/records?since=` | Get records since timestamp |
| `GET` | `/sync/aliases?since=` | Get aliases since timestamp |
| `GET` | `/sync/epochs?since=` | Get epochs since timestamp |
| `POST` | `/sync/push` | Push batch to peer |

## Security Model

### What GNS Nodes CAN Do
- Store and serve signed GNS Records
- Relay encrypted messages
- Gossip with peer nodes
- Enforce PoT requirements

### What GNS Nodes CANNOT Do
- **Forge identities**: All records require valid Ed25519 signature
- **Read messages**: E2E encrypted with recipient's PK
- **Fake breadcrumbs**: Chain is local; only commitments published
- **Steal handles**: Claims require valid signature + PoT proof

## Deployment

### Railway

1. Connect your GitHub repo
2. Add environment variables in Railway dashboard
3. Deploy!

### Docker

```bash
docker build -t gns-node .
docker run -p 3000:3000 --env-file .env gns-node
```

## Project Structure

```
gns-node/
├── src/
│   ├── api/
│   │   ├── records.ts      # /records endpoints
│   │   ├── aliases.ts      # /aliases endpoints
│   │   ├── epochs.ts       # /epochs endpoints
│   │   ├── messages.ts     # /messages endpoints
│   │   └── sync.ts         # /sync endpoints
│   ├── lib/
│   │   ├── crypto.ts       # Ed25519 verification
│   │   ├── db.ts           # Supabase client
│   │   └── validation.ts   # Zod schemas
│   ├── types/
│   │   └── index.ts        # TypeScript types
│   └── index.ts            # Express app entry
├── Dockerfile
├── package.json
├── tsconfig.json
└── .env.example
```

## Handle Claiming Requirements

To claim an @handle, you need:
- **100+ breadcrumbs** in your chain
- **20%+ trust score**
- First valid claim wins

## License

MIT

---

*"Your identity is not discovered. It is announced. To everyone. Forever."*
