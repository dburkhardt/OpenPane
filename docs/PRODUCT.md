# Product contract

OpenPane is a lightweight native file inspector and text editor, not a general
IDE or publishing suite.

## Core behavior

1. Reading never writes the source file. Text is selectable but immutable until
   **Edit** is chosen, and files are saved only through an explicit command.
2. File bytes are authoritative. OpenPane preserves encoding, BOM, line-ending
   convention, final-newline state, POSIX permissions, and extended attributes.
3. Specialized formats remain specialized. Markdown is rendered, PDFs use
   PDFKit, and system-previewable files use a read-only preview.
4. Unknown binary originals are inspect-only. Any editable conversion is a new
   UTF-8 text file.
5. OpenPane never executes or uploads opened content, expands archives, or
   automatically fetches remote resources.

## Workspace behavior

- One authorized folder per window
- Lazy tree, filename Quick Open, preview and pinned tabs
- At most two editor groups
- Basic create, rename, duplicate, move, reveal, path-copy, and Trash actions
- Useful source dotfiles visible; generated and VCS internals hidden behind
  **Show All Files**
- Loose files open without implicitly granting access to their parent folder

## Deliberate non-goals

- Project-wide search or Replace in Files
- Git, terminal, debugger, build tasks, extensions, or language servers
- PDF editing, annotation, form-filling, raw-byte, or signature tools
- Binary editing
- Giant-file editing
- Publishing, proofreading, custom processors, or export pipelines
- Quick Look extensions or Finder extensions
