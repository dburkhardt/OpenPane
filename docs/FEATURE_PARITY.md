# Feature parity

This matrix is based on the products' public feature descriptions as of
2026-07-23. It is a product requirements inventory, not an instruction to copy
their visual design.

Legend: **Done**, **Next**, **Planned**, **Research**

| Capability | Glance | Marked 3 | FreeMark |
|---|---:|---:|---:|
| Open Markdown directly | Yes | Yes | **Done** |
| Rendered reading view | Yes | Yes | **Done** (core syntax) |
| Native source editing | Yes, Pro | No | **Done** |
| Source/preview split view | — | External editor | **Done** |
| Inline rendered editing | Yes, Pro | No | **Planned** |
| Visual table editing | Yes, Pro | No | **Planned** |
| Mermaid source editing | Yes, Pro | Preview | **Planned** |
| GFM tables and task lists | Yes | Yes | **Next** |
| Syntax-highlighted code | Yes | Yes | **Next** |
| Mermaid diagrams | Yes | Yes | **Next** |
| LaTeX math | Yes | Yes | **Next** |
| File-change watching | — | Yes | **Next** |
| Finder Quick Look | Yes | Add-on | **Next** |
| Search with highlights | Yes | Yes | **Next** |
| Outline / table of contents | — | Yes | **Done** |
| Pinch/semantic zoom | Yes | — | **Planned** |
| Themes | Yes | Yes | **Planned** |
| Custom CSS | — | Yes | **Planned** |
| Local proofreading | — | Advanced | **Done** (baseline) |
| Link validation | — | Yes | **Planned** |
| Word repetition / readability stats | — | Yes | **Done** (baseline) |
| HTML export | — | Yes | **Done** (baseline) |
| PDF export | — | Yes | **Next** |
| DOCX export | — | Yes | **Planned** |
| EPUB export | — | Yes | **Planned** |
| Export profiles / batch export | — | Yes | **Planned** |
| Custom Markdown processors | — | Yes | **Research** |
| Scrivener project preview | — | Yes | **Research** |
| Word / tracked-change workflows | — | Yes | **Research** |
| Presentation mode | — | — | **Planned** |
| Fully offline core | Yes | Yes | **Required** |
| Free and open source | No (editing) | No | **Required** |

## Existing free alternatives

No single free *native macOS* app found in the audit covers the combined
feature set.

- **Glassmark** is the closest native editor: live SwiftUI editing/preview,
  Mermaid, KaTeX, PDF/HTML, custom CSS, folder workspaces, and an outline. It
  does not advertise Quick Look, rendered inline/table editing, DOCX/EPUB, or
  Marked-style proofreading and integrations.
- **MDViewer** is free and open source with file watching, editing, Mermaid,
  KaTeX, an outline, and PDF export. It does not advertise Quick Look,
  professional publishing formats, custom CSS, or proofreading.
- **Glyph** covers an unusually broad set, including DOCX/EPUB, but is a
  cross-platform Tauri/React application rather than a native SwiftUI/AppKit
  Mac app.

## Sources

- Glance: <https://glance.md/>
- Marked 3: <https://markedapp.com/markdown-preview/>
- Glassmark: <https://glassmark.net/>
- MDViewer: <https://masakai.github.io/mdviewer/>
- Glyph: <https://glyph-md.github.io/>
