# Changelog

All notable changes will be documented here.

## 0.1.0 — file workspace beta

- Product pivot to a lightweight, read-first file workspace
- One-folder workspaces, loose-file windows, tabs, splits, and Quick Open
- Explicit text editing and saving with byte/encoding preservation
- Curated Tree-sitter syntax highlighting
- GFM Markdown, PDFKit, system-preview, decoded-text, and hex viewers
- App Sandbox and text-only Finder registration

This release remains a prerelease and intentionally omits IDE, publishing, PDF
editing, binary editing, and project-wide search features.

## 0.0.2 — signing correction

- Developer ID Application signing with Hardened Runtime and secure timestamps
- Apple notarization with a fail-closed tagged-release workflow
- Stapled notarization tickets and Gatekeeper validation
- Final release archives, checksums, and provenance generated after stapling
- Secret-free CI artifacts explicitly labeled as ad-hoc developer previews

OpenPane remains an early prototype, but this release is suitable for normal
Gatekeeper verification on supported Macs.

## 0.0.1 — prototype preview

- Native SwiftUI Markdown/plain-text document shell
- Preview, source, and split modes
- Prototype Markdown renderer and stable outline navigation
- Baseline local proofreading and HTML export
- MIT license and OpenPane product identity
- Reproducible Apple Silicon `.app` packaging
- macOS 26 CI and tag-driven GitHub prereleases

This historical preview is ad-hoc signed, not Apple-notarized, and predates the
file-workspace pivot.
