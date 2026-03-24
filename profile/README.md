# ShrouDB

**Encrypted credential management, transit encryption, and authentication — built in Rust.**

ShrouDB is a suite of security-focused servers designed for applications that need centralized, encrypted-at-rest credential storage, encryption-as-a-service, and turnkey authentication. Every component is written in Rust, ships as a single static binary, and communicates over the RESP3 wire protocol with TLS/mTLS support.

---

## Repositories

### [`shroudb`](https://github.com/shroudb/shroudb) — Credential Vault

The core server. Manages JWT signing keys, API keys, HMAC secrets, refresh tokens, and passwords with automatic key rotation, encrypted WAL-based storage, and a Pub/Sub event system.

- **5 credential types** — JWT (ES256, RS256, EdDSA, …), API Key, HMAC, Refresh Token, Password (Argon2id/bcrypt/scrypt)
- **Encrypted at rest** — AES-256-GCM with per-keyspace HKDF-derived keys
- **Durable** — Write-ahead log with periodic snapshots, CRC32 integrity checks, crash recovery
- **Observable** — Prometheus metrics, structured JSON audit logging, webhook notifications
- **Deployable** — Docker (`shroudb/shroudb`), Homebrew, static binaries, Helm charts, systemd

### [`shroudb-transit`](https://github.com/shroudb/shroudb-transit) — Encryption as a Service

Offload all cryptographic operations to a dedicated server. Applications never touch plaintext keys — they send data in, get ciphertext back.

- **Encrypt / Decrypt / Rewrap** — AES-256-GCM and ChaCha20-Poly1305 with context binding (AAD)
- **Sign / Verify** — HMAC-SHA256, Ed25519, ECDSA-P256
- **Envelope encryption** — `GENERATE_DATA_KEY` for client-side patterns
- **Key lifecycle** — Staged → Active → Draining → Retired, with automatic rotation
- **Convergent encryption** — Opt-in deterministic mode for encrypted search (triple safety gate)

### [`shroudb-auth`](https://github.com/shroudb/shroudb-auth) — Authentication Server

A standalone REST API for user authentication and session management, backed by ShrouDB.

- **JWT + Refresh Token rotation** — Family-based revocation, configurable signing algorithms
- **Password hashing** — Argon2id (default), bcrypt, scrypt with transparent rehash on login
- **Security hardening** — Per-IP rate limiting, CSRF protection, account lockout, CORS
- **Multi-keyspace** — Isolate auth for different apps or tenants from a single instance
- **Two modes** — Embedded (ShrouDB in-process) or Remote (stateless proxy to external ShrouDB)

### [`commons`](https://github.com/shroudb/commons) — Shared Libraries

Three foundational crates consumed by all ShrouDB services:

| Crate | Purpose |
|---|---|
| `shroudb-crypto` | Key generation, AEAD, HKDF, JWT, HMAC, password hashing, signing |
| `shroudb-core` | Domain types, credential state machines, keyspace config, metadata schemas |
| `shroudb-storage` | Encrypted WAL, snapshots, crash recovery, in-memory indexes, key management |

### [`shroudb-codegen`](https://github.com/shroudb/shroudb-codegen) — SDK Code Generator

Generates typed client SDKs from TOML spec files for both the RESP3 wire protocol and HTTP APIs.

- **Languages** — Python, TypeScript, Go, Ruby, Protobuf/gRPC
- **Dual mode** — Wire protocol clients and REST API clients from a single tool
- **Complete packages** — Generates connection pooling, pipelines, error handling, and package metadata

---

## Install

### Homebrew

```sh
brew tap shroudb/tap
brew install shroudb           # credential vault + CLI
brew install shroudb-transit   # encryption-as-a-service + CLI
brew install shroudb-auth      # authentication server
```

### Docker

```sh
docker pull shroudb/shroudb       # credential vault
docker pull shroudb/transit       # encryption-as-a-service
docker pull shroudb/auth          # authentication server
```

CLI images: `shroudb/cli`, `shroudb/transit-cli`

### Binary

Prebuilt static binaries for Linux (x86_64, aarch64) and macOS (x86_64, Apple Silicon) are available on each repository's [Releases](https://github.com/shroudb) page.

---

## Design Principles

| Principle | How |
|---|---|
| **Fail closed** | Disk full, key unavailable, corruption → reject rather than serve incorrect results |
| **Encryption everywhere** | All data encrypted at rest; double-layer encryption for private keys |
| **Zero plaintext on disk** | Transit server never persists plaintext — only encrypted key material |
| **Memory safety** | `mlock`-pinned secrets, `zeroize`-on-drop, core dumps disabled, constant-time comparisons |
| **Single binary** | Each server compiles to one static binary — no runtime dependencies |

## Tech Stack

**Rust** · Tokio · Ring · AES-256-GCM · HKDF-SHA256 · RESP3 · Axum · Prometheus · Docker · Homebrew

## License

All repositories are licensed under **MIT OR Apache-2.0**.
