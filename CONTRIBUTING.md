# Contributing to HeadsetGuard

Thanks for helping improve HeadsetGuard! This guide covers how to get set up and what we look for in a pull request.

## Getting started

Requirements: macOS 11+ and the Xcode Command Line Tools (`xcode-select --install`). There are no third-party dependencies.

```bash
git clone https://github.com/Akpahsamuel/HeadsetGuard.git
cd HeadsetGuard
make build      # compile and package build/HeadsetGuard.app
make test       # run the automated test suite
make run        # launch it
make cli        # create bin/headsetguard symlink for CLI testing
make clean      # remove build/ and bin/
```

SwiftPM discovers and builds sources automatically under `Sources/`. Run `make test` to execute the Swift Testing suite.

## Ways to contribute

- Report bugs or request features through [issues](https://github.com/Akpahsamuel/HeadsetGuard/issues).
- Test with headsets we haven't (AirPods, Sony, Bose, Galaxy Buds, generic) and report quirks.
- Pick up an issue labelled `good first issue` or `help wanted`.
- Improve docs, add tests in `Tests/HeadsetGuardKitTests`, or enhance features.

**Security vulnerabilities:** do not open a public issue. See [SECURITY.md](SECURITY.md).

## Pull request workflow

1. Fork the repo and create a branch from `main` (`fix/short-name` or `feat/short-name`).
2. Keep the change focused: one fix or feature per PR.
3. Build with no new warnings and ensure `make test` passes (`swift test`).
4. Update the README or docs if behaviour changes.
5. Open the PR and fill in the template. Describe what changed, why, and how you tested it.

### Commit messages

Use short, imperative, conventional-style subjects, for example `fix: avoid double unlock prompt on wake` or `feat: add --version flag`.

## Code guidelines

- Native Swift 6 (language mode 5) with SwiftPM. Use weak references for delegates and break retain cycles.
- Match the style of the surrounding code (naming, spacing, comment density).
- Check CoreAudio / IOBluetooth return values. On errors, **fail closed**: the headset stays muted.
- Keep `AudioGuard` state access on its serial queue.
- Never store secrets in `UserDefaults` or write them to logs. Credentials belong in the Keychain.
- Don't add third-party dependencies without discussing it in an issue first.
- Note: `resources/generate_icon.m` is a standalone Objective-C tool for generating AppIcon vector assets.
- Don't commit build output (`build/`, `bin/`, `.build/`).

## Conduct

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). By contributing, you agree your work is licensed under the [MIT License](LICENSE).
