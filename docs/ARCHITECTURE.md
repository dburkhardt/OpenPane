# Architecture

## Process structure

OpenPane remains a Swift Package Manager application:

```text
OpenPane
├── OpenPaneCore     byte-safe file model, classification, I/O, language metadata
├── OpenPane         SwiftUI workspace shell and AppKit-backed viewers/editor
├── OpenPaneCoreTests
└── OpenPaneTests
```

`WorkspaceSession` owns a security-scoped folder, tree state, tabs, and at most
two editor groups. `FileSession` owns one canonical buffer and is shared by
every view of the same file. File content never becomes workspace metadata.

## Opening

The classifier reads a bounded prefix and evaluates specialized signatures and
UTTypes before attempting a lossless text decode. PDFs always route to PDFKit.
Known text routes to the source editor or Markdown reader. Recognized non-text
formats route to the system preview. Remaining data routes to the binary
inspector.

## Editing and saving

The source editor is an `NSTextView` using TextKit 2. Rendering attributes from
Tree-sitter never enter the serialized text. A file retains its original byte
snapshot and metadata until an explicit save.

Saves strict-encode the buffer, verify the source fingerprint, coordinate the
write, and atomically replace the file. Clean external changes reload; dirty
changes require an explicit conflict decision. Recovery snapshots live in
Application Support and never overwrite the source.

## Security

- App Sandbox with user-selected read/write access and app-scoped bookmarks
- No network entitlement and no automatic remote Markdown resources
- No document scripts, macros, processors, archive expansion, or code execution
- Directory symlinks are not recursively traversed
- Finder registration is `public.text`, never `public.data` or PDF
