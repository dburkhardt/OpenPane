# OpenPane

OpenPane is a free, open-source, read-first file workspace for macOS. It is
designed for the common job of opening a folder, inspecting Markdown, JSON,
source code, logs, PDFs, and unfamiliar files, and making an occasional
explicit text edit without launching a full IDE.

> [!IMPORTANT]
> OpenPane 0.1 is a focused public prerelease, not a full IDE. Large-file
> editing, project-wide search, Git, terminal, debugger, LSP, and extensions
> remain deliberately out of scope.

## Product contract

- Native macOS 26+ application for Apple Silicon
- One folder per workspace window, plus lightweight loose-file windows
- Markdown reader, PDF reader, safe system previews, and binary inspection
- Read-only syntax-highlighted source until the user chooses **Edit**
- Explicit saves: merely opening or reading a file never writes it
- Local and offline by default, with no account or telemetry
- MIT-licensed source and Developer ID signed/notarized releases from `v0.0.2`
  onward

OpenPane is intentionally not an IDE. It does not include a terminal, Git UI,
debugger, language server, extension host, formatter, or project-wide search.
It also does not edit PDFs or binary originals.

## Build and test

Requirements: macOS 26 or later and Xcode 26 or later.

```sh
swift test
./scripts/build-app.sh
open dist/OpenPane.app
```

Main-branch and pull-request artifacts are ad-hoc-signed developer previews.
Tagged releases from `v0.0.2` onward are signed with Developer ID, notarized by
Apple, stapled, and validated by Gatekeeper. See
[`docs/RELEASING.md`](docs/RELEASING.md).

## File handling

Finder registration is limited to `public.text`, so OpenPane appears for text,
Markdown, JSON, logs, source, and configuration files without competing with
Preview for PDFs or media. A workspace can still display PDFs and other
recognized files encountered in its folder.

Unknown binary files open in bounded, read-only decoded-text and hex views.
Creating editable text always produces a separate UTF-8 copy.

Text files up to 20 MiB support normal editing and highlighting. Larger text
files and binary inspection use bounded, read-only views; large Markdown
rendering, outlining, and wrapping are disabled.

## Project documentation

- [`docs/PRODUCT.md`](docs/PRODUCT.md) — behavior and safety contract
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — session, I/O, editor, and viewer design
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — current delivery status
- [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) — dependency licenses

## License

OpenPane is released under the [MIT License](LICENSE).
