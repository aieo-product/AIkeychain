# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in AI KeyChain, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please send an email or use [GitHub Security Advisories](https://github.com/aieo-product/AIkeychain/security/advisories/new).

### What to include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response timeline

- **Acknowledgement**: within 48 hours
- **Initial assessment**: within 1 week
- **Fix release**: as soon as possible after confirmation

## Security Design

AI KeyChain is designed with security as a core principle:

- **All API keys are stored in macOS Keychain** (encrypted at rest, hardware-backed)
- **Proxy mode** ensures keys never appear in environment variables
- **Proxy binds to localhost only** (127.0.0.1) — no external access
- **Key transfer** uses P-256 ECDH + AES-256-GCM encryption
- **Private keys** are stored in Keychain and cannot be exported

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.5.x   | ✅        |
| < 1.5   | ❌        |
