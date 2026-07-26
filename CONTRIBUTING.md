# Contributing to OpenPane

OpenPane is a read-first native macOS file workspace. Contributions are
welcome. Read the [product contract](docs/PRODUCT.md) and
[architecture](docs/ARCHITECTURE.md) before starting a large change.

## Development requirements

- Apple Silicon Mac
- macOS 26 or later
- Xcode 26 or later

Run the checks:

```sh
swift test
./scripts/check-third-party-notices.sh
./scripts/package-release.sh 0.1.0
```

## Pull requests

- Keep each change focused.
- Add or update tests for behavior changes.
- Describe user impact and validation in the pull request.
- Do not commit `.build`, `dist`, credentials, signing material, or generated
  archives.
- Preserve the original file as the canonical source.
- Keep reading safe and side-effect-free by default.

## Security-sensitive changes

Changes involving file classification, decoding, coordinated writes,
security-scoped bookmarks, previews, URLs, symlinks, signing, or updates require
explicit threat cases and security tests. Report vulnerabilities according to
[SECURITY.md](SECURITY.md).
