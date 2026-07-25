# OpenPane

OpenPane is a free, open-source, read-first Markdown app for macOS. It is being
built to present documents as a beautiful native reading surface by default,
with explicit editing and publishing tools when needed. It is a clean-room
project inspired by useful workflows in Glance and Marked 3; it does not copy
either product's branding, interface, assets, or proprietary implementation.

> [!IMPORTANT]
> OpenPane is currently an early prototype, not a Glance/Marked replacement.
> The implemented subset is listed below; the complete plan is linked under
> **Project status**.

## What works now

- Native SwiftUI document app for `.md` and plain-text files
- Preview, source, and split modes
- Autosave, undo, multiple windows, and standard document behavior
- Rendered headings, paragraphs, inline emphasis, links, flat unordered/task
  lists, one-line quotes, dividers, and fenced code blocks
- Clickable document outline
- Adjustable type size and reading width
- Four local, offline proofreading checks and word count
- Basic standalone HTML export using the prototype parser

## Run it

Requirements: macOS 26 or later and Xcode 26 or later.

```sh
swift run
```

Build a normal app bundle:

```sh
./scripts/build-app.sh
open dist/OpenPane.app
```

Build, test, and create a release archive:

```sh
swift test
./scripts/package-release.sh 0.0.1
```

Tagged GitHub builds publish an ad-hoc-signed prerelease, checksum, and build
provenance. Developer ID signing and Apple notarization are required before
OpenPane offers a normal end-user release.

## Target product principles

1. Native Mac interaction: SwiftUI/AppKit, document windows, system find,
   Services, Shortcuts, Quick Look, and standard menus.
2. Local-first: reading, editing, proofreading, and core export work offline.
3. Plain files: no library import and no proprietary database.
4. One renderer: the app, Quick Look, and every export share a conformance
   suite so documents do not change shape between surfaces.
5. Extensible publishing: CSS themes, custom processors, and export profiles
   are first-class, but execute with explicit permissions.
6. Clean-room parity: reproduce useful capabilities, not protected expression.

## Project status

This is milestone 0: a compiling architectural slice. See
[`docs/FEATURE_PARITY.md`](docs/FEATURE_PARITY.md) and
[`docs/ROADMAP.md`](docs/ROADMAP.md). The complete product plan, architecture,
acceptance criteria, and release boundaries are in
[`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).

## License

OpenPane is released under the [MIT License](LICENSE).
