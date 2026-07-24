# FreeMark

FreeMark is a free, open-source, native macOS Markdown reader, editor, and
publishing tool. It is a clean-room feature-parity project inspired by the
useful workflows of Glance and Marked 3. It does not copy either product's
branding, interface, assets, or proprietary implementation.

The name is provisional.

## What works now

- Native SwiftUI document app for `.md` and plain-text files
- Preview, source, and split modes
- Autosave, undo, multiple windows, and standard document behavior
- Rendered headings, paragraphs, inline emphasis, links, lists, task items,
  quotes, dividers, and fenced code blocks
- Clickable document outline
- Adjustable type size and reading width
- Local, offline proofreading checks
- Standalone HTML export

## Run it

Requirements: macOS 14 or later and Xcode 16 or later.

```sh
swift run
```

Build and test:

```sh
swift build
swift test
```

## Product principles

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
[`docs/ROADMAP.md`](docs/ROADMAP.md).

## License

The intended license is MIT. A final copyright owner should be chosen before
the first public release.
