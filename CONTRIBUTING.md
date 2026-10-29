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

If you add a source file, add it to `SRCS` in the [Makefile](Makefile).

## Ways to contribute

- Report bugs or request features through [issues](https://github.com/Akpahsamuel/HeadsetGuard/issues).
- Test with headsets we haven't (AirPods, Sony, Bose, Galaxy Buds, generic) and report quirks.
- Pick up an issue labelled `good first issue` or `help wanted`.
- Improve docs, and add tests (there is no test suite yet; a test target would be very welcome).

**Security vulnerabilities:** do not open a public issue. See [SECURITY.md](SECURITY.md).

## Pull request workflow

1. Fork the repo and create a branch from `main` (`fix/short-name` or `feat/short-name`).
2. Keep the change focused: one fix or feature per PR.
3. Build with no new warnings (`-Wall -Wextra` is enabled) and try the change on real hardware where possible.
4. Update the README or docs if behaviour changes.
5. Open the PR and fill in the template. Describe what changed, why, and how you tested it.

### Commit messages

Use short, imperative, conventional-style subjects, for example `fix: avoid double unlock prompt on wake` or `feat: add --version flag`.

## Code guidelines

- Objective-C with ARC. Use `__weak`/`__strong` in blocks, and copy weak delegates to a strong local before messaging them.
- Match the style of the surrounding code (naming, spacing, comment density).
- Check allocation results and CoreAudio/IOBluetooth status codes. On errors, **fail closed**: the headset stays muted.
- Keep `AudioGuard` state access on its serial queue.
- Never store secrets in `NSUserDefaults` or write them to logs. Credentials belong in the Keychain.
- Don't add third-party dependencies without discussing it in an issue first.
- Don't commit build output (`build/`, `bin/`).

## Conduct

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). By contributing, you agree your work is licensed under the [MIT License](LICENSE).
