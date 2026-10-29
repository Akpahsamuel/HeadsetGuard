# Security Policy

HeadsetGuard is a security tool, so we take vulnerability reports seriously.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report privately using GitHub's [private vulnerability reporting](https://github.com/Akpahsamuel/HeadsetGuard/security/advisories/new) (the repository's **Security** tab, then **Report a vulnerability**).

Include:
- A description of the issue and its impact
- Steps to reproduce, with macOS version and headset model
- Any proof-of-concept code or logs (with secrets removed)

You can expect an acknowledgement within a few days. We'll work on a fix, keep you updated, and credit you in the release notes if you wish.

## Scope

In scope: ways to bypass the lock, recover or brute-force the master PIN, leak credentials or audit logs, or tamper with enforcement.

Out of scope: attacks that already require root access or a fully compromised, unlocked Mac, and weaknesses in Bluetooth headset firmware itself.

## Supported versions

Only the latest commit on `main` is supported.
