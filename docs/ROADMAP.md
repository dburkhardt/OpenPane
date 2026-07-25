# Roadmap

## M0 — Architectural slice

- [x] SwiftUI document app
- [x] Source, preview, and split modes
- [x] Outline navigation
- [x] Baseline local proofreader
- [x] Baseline HTML export
- [x] Parser and proofreader tests

Exit: the project builds and the core model is independently testable.

## M1 — Faithful renderer

- Adopt `swift-markdown` as the CommonMark/GFM syntax tree
- Build reusable render nodes for app, Quick Look, HTML, and print
- GFM tables, ordered/nested lists, footnotes, alerts, and task toggling
- Local and bounded remote images
- Sanitized raw HTML
- Tree-sitter syntax highlighting
- KaTeX-compatible math layout
- Mermaid rendering with an offline, sandboxed renderer
- Golden fixture suite for light/dark and export parity

Exit: representative GitHub READMEs and AI-generated documents render without
meaningful loss.

## M2 — Mac viewer

- File coordination and external-change watching
- Native find bar with result highlights
- Tabs, recent documents, link routing, restored scroll positions
- Quick Look Preview Extension sharing the renderer
- Pinch zoom and reading-width presets
- App sandbox and hardened runtime

Exit: OpenPane can replace a code editor for everyday Markdown reading.

## M3 — Editing

- Selection-preserving source editor with syntax styling
- Rendered-block editing
- Formatting popover and keyboard commands
- Visual table row/column operations
- Mermaid source overlay with live validation
- Drag/drop and image paste with relative-path policies

Exit: all Glance Pro editing workflows have a free equivalent.

## M4 — Proofreading

- Repetition, passive voice, sentence length, readability, and jargon rules
- User dictionaries, ignore rules, and rule profiles
- Link and image validation
- Statistics HUD and issue navigation into source
- Optional local language-model provider behind an explicit switch

Exit: the core editorial workflow is useful without a network service.

## M5 — Publishing and integrations

- Print-quality PDF
- Standalone HTML
- DOCX and EPUB
- Export profiles and batch export
- Custom CSS and document styles
- Custom processors with scoped file/network permissions
- Scrivener package ingestion research
- Word DOCX and tracked-change ingestion research

Exit: the common Marked 3 publishing workflow has a free equivalent.

## M6 — Release

- Accessibility audit and full keyboard navigation
- Large-file and hostile-input benchmarks
- Signed/notarized builds and Sparkle updates
- Homebrew cask
- Reproducible builds, SBOM, privacy manifest

Exit: a safe public beta can become the default handler for `.md` files.

## Explicit non-goals

- Copying either comparison app's name, icon, screenshots, layout, or CSS
- Compatibility that requires reverse engineering proprietary code
- Cloud accounts, subscriptions, telemetry, or mandatory AI
- Executing document scripts by default
