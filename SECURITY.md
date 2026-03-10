# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in McClaw, please report it responsibly.

**Do not open a public issue.**

Instead, please email: **j.conti@joseconti.com**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: within 48 hours
- **Initial assessment**: within 1 week
- **Fix and release**: as soon as practical, depending on severity

## Security Model

McClaw is designed with security as a priority:

- **Execution Approvals** — Glob-based allow/deny rules for commands executed by AI
- **Environment Sanitization** — Sensitive environment variables are stripped before passing to CLIs
- **Keychain Storage** — OAuth tokens and credentials are stored in the macOS Keychain
- **TCC Compliance** — Proper macOS permission handling for microphone, screen recording, camera, and location
- **IPC Authentication** — Unix socket communication uses HMAC + UID verification
- **No API keys stored** — Authentication is delegated to each CLI's own auth flow

## Scope

The following are in scope for security reports:

- Command injection via chat input or file attachments
- Credential leakage (tokens, keys, sensitive environment variables)
- Unauthorized file system access
- Bypass of execution approval rules
- IPC authentication bypass
- Privacy violations (unauthorized microphone, camera, or screen access)

## Acknowledgments

We appreciate the security research community and will credit reporters (with permission) in release notes.
