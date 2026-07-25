# Contributing to OpenPane

OpenPane is an early, read-first macOS Markdown project. Contributions are
welcome, but the architecture is intentionally being replaced in phases. Check
the [implementation plan](docs/IMPLEMENTATION_PLAN.md) before starting a large
change.

## Development requirements

- Apple Silicon Mac
- macOS 26 or later
- Xcode 26 or later

Run the checks:

```sh
swift test
./scripts/package-release.sh 0.0.1
```

## Pull requests

- Keep each change focused.
- Add or update tests for behavior changes.
- Describe user impact and validation in the pull request.
- Do not commit `.build`, `dist`, credentials, signing material, or generated
  archives.
- Preserve plain Markdown as the canonical source.
- Keep reading safe and side-effect-free by default.

## Clean-room rule

OpenPane may reproduce useful capabilities described publicly by other
products. Do not copy proprietary code, assets, CSS, screenshots, wording, or
distinctive interface expression.

## Security-sensitive changes

Changes involving raw HTML, WebKit, remote resources, URLs, file access,
processors, signing, or updates require explicit threat cases and security
tests. Report vulnerabilities according to [SECURITY.md](SECURITY.md).
