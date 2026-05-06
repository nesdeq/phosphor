# Security Policy

## Supported versions

PHOSPHOR is pre-1.0. Only the latest tagged release on `main` receives security fixes.

| Version | Supported |
|---|---|
| Latest release on `main` | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report privately via GitHub's **[Private Security Advisory](https://github.com/nesdeq/phosphor/security/advisories/new)** form.

We aim to acknowledge reports within **72 hours** and ship a fix or mitigation within **30 days** for confirmed high/critical issues. Lower-severity issues ship in the next regular release.

When reporting, please include:
- A clear description of the issue and impact
- Steps to reproduce, ideally a minimal proof of concept
- Affected version(s) / commit hash
- Your assessment of severity and any mitigations you're aware of

## Scope

In scope:
- The PHOSPHOR client app (`lib/`)
- The relay server (`server/relay_server.dart`)
- Build & release pipeline (`.github/workflows/`)
- Documentation that could mislead users into insecure setups

Out of scope:
- Vulnerabilities in third-party dependencies — please report those upstream. We track Dependabot alerts and will rev pinned versions.
- Issues that require physical access to the user's machine
- Self-inflicted misconfigurations (e.g. publishing your `private.pem`)
- Social engineering of session-code holders

## Cryptography summary

The multiplayer feature is end-to-end encrypted. The relay server is a routing pipe and never sees plaintext.

- **Transport:** TLS 1.2+ over WebSocket (`wss://`) with **certificate pinning**. The client compares the server's exact DER-encoded certificate against the user-supplied `public.pem`. Any other cert — including a valid CA-signed one — is rejected.
- **Key derivation:** HKDF-SHA256 over the encryption secret half of the session code (`PHO-XXXXXX-YYYYYYYYYYYY` — only the second segment is used as the secret; the first segment is opaque routing). 32-byte output.
- **Symmetric encryption:** AES-256-GCM. Each message generates a fresh random 12-byte nonce. The `msgType` (`output` / `input` / `resize`) is bound as AAD to prevent type confusion across message kinds.
- **Replay protection:** Decryption maintains an LRU set of the last 1024 nonces seen per session and rejects duplicates.

The session code is generated client-side from a CSPRNG (`Random.secure()`), 30 bits of routing entropy + 60 bits of secret entropy.

If you find a deviation from this model, a downgrade attack, a side channel, or a flaw in the relay protocol that lets the server learn anything about session content beyond its size and timing — please report it.

## Known caveats (not vulnerabilities)

- The relay observes message **timing** and **ciphertext sizes**. This is true of any E2E channel without padding. Not a regression we plan to address.
- A hostile peer who has been admitted to a session and granted **Editor** can type arbitrary input into the host's shell. This is by design — the host is responsible for who they admit and what role they grant. Don't grant Editor to people you don't trust to use your shell.
- macOS release builds are not Apple-signed. The `xattr -dr com.apple.quarantine` workaround is documented in [README.md](README.md). This is a distribution friction issue, not a security defect — users who don't trust the binary should build from source.

## Coordinated disclosure

We publish a GitHub Security Advisory once a fix has shipped, including a CVE if one was assigned. Reporters are credited unless they prefer to remain anonymous.
