# OpenPane implementation plan

Status: approved product direction, milestone-0 implementation  
Target: macOS 26+, Apple Silicon, free and open source under MIT

## 1. Product contract

OpenPane is a personal-first Markdown reader for macOS. Its default experience
is a visually exceptional, nearly chrome-free document—not an editor with a
preview attached.

The product must:

- open Markdown naturally from Finder and provide an excellent Quick Look
  preview;
- render the agent and project documents we actually use, including tables,
  code, Mermaid, images, links, task lists, and sanitized HTML;
- notice external file changes quietly and update without stealing focus or
  losing the reader's place;
- keep source files authoritative, with no import step or proprietary library;
- expose editing only through an explicit **Edit** action;
- work offline for core reading, editing, proofreading, and export;
- remain free, open source, account-free, and telemetry-free;
- use native SwiftUI/AppKit interaction, with isolated WebKit only where it
  materially improves rendering;
- support automatic remote images with strict resource limits and a setting to
  disable them.

## 2. Honest starting point

The current code is an architectural prototype, not a full application.

It currently provides:

- a SwiftUI `DocumentGroup` that opens and saves UTF-8 Markdown/plain text;
- preview, source, and split modes;
- a small handwritten parser for headings, paragraphs, flat unordered/task
  lists, one-line quotes, dividers, and fenced code;
- basic inline emphasis and links through Foundation's inline Markdown parser;
- a document outline, simple type/width settings, four regex proofreading
  checks, word count, and basic HTML export;
- two parser/proofreader tests;
- a reproducible script that builds an ad-hoc-signed `.app`.

It does not yet provide:

- faithful CommonMark/GFM parsing, tables, nested or ordered lists, footnotes,
  alerts, images, sanitized HTML, Mermaid, math, or syntax highlighting;
- Quick Look, Finder-grade document integration, file watching, preserved
  scroll position, search highlights, or polished reader chrome;
- an explicit Edit lifecycle, rendered editing, table editing, image paste,
  source/preview synchronization, or conflict handling;
- PDF, DOCX, EPUB, themes, custom CSS, export profiles, link validation, or
  advanced proofreading;
- an app sandbox, production signing, notarization, stapling, or a real app
  icon;
- UI, integration, renderer-conformance, performance, security, or export
  tests.

## 3. Release boundaries

Two product boundaries keep the reader from being delayed indefinitely:

### OpenPane 1.0 — complete reader

OpenPane 1.0 is the product selected in the interview:

- faithful Markdown/GFM rendering;
- tables, code highlighting, Mermaid, math, local/remote images, and sanitized
  HTML;
- Finder opening and Quick Look;
- quiet external updates with semantic position preservation;
- outline, find, links, keyboard navigation, accessibility, tabs/windows, and
  restored reading positions;
- occasional source edits behind explicit Edit/Done;
- polished HTML and PDF export;
- signed, notarized, reproducible public releases.

### OpenPane 2.0 — complete editing and publishing suite

OpenPane 2.0 completes the broader Glance Pro and Marked-style capability set:

- source-mapped editing, formatting, visual table operations, and Mermaid
  editing;
- advanced proofreading, dictionaries, profiles, statistics, and validation;
- themes, custom CSS, export profiles, batch publishing;
- DOCX and EPUB;
- carefully sandboxed custom processors, if the security design proves viable;
- gated research integrations such as Scrivener and tracked-change workflows.

This is capability parity, not visual or implementation copying. OpenPane will
not reproduce another product's branding, assets, CSS, wording, or protected
interface expression.

## 4. Target architecture

Replace the single executable target with an Xcode workspace and reusable Swift
packages:

```text
OpenPane.xcworkspace
├── OpenPaneApp
├── OpenPaneQuickLook
├── Packages
│   ├── OpenPaneCore
│   ├── MarkdownEngine
│   ├── RenderKit
│   ├── ResourceKit
│   ├── EditorKit
│   ├── ProofreadingKit
│   └── ExportKit
└── Tests
    ├── Fixtures
    ├── GoldenImages
    ├── Integration
    └── UITests
```

### Core rules

1. **One semantic tree**

   A pinned CommonMark/GFM parser feeds an OpenPane-owned semantic tree with
   stable node IDs and exact source ranges. The app, Quick Look, editing
   navigation, proofreading, HTML, and PDF all consume this representation.

2. **Canonical source wins**

   The source file is authoritative. Parsing and rendering produce revisioned
   snapshots; stale asynchronous results are discarded.

3. **Native first, isolated web where necessary**

   Render prose, lists, tables, code, images, and callouts natively. Use locked
   down local `WKWebView` instances for Mermaid, math, and any retained safe HTML
   fragment. Document content cannot supply executable JavaScript.

4. **Coordinated files**

   Put `NSFileCoordinator`/`NSFilePresenter` behind a document-session actor.
   Debounce write bursts, compare content hashes, surface real conflicts, and
   restore position from semantic block ID plus intra-block offset.

5. **Controlled resources**

   Fetch remote images through an ephemeral `URLSession`, never directly from
   document HTML. Strip credentials and referrers; bound redirects, bytes,
   decoded pixels, concurrency, and cache size. Decide HTTP, private-network,
   SVG, and Quick Look network behavior explicitly.

6. **Real Mac editing**

   Use an AppKit `NSTextView`/TextKit 2 editor for explicit source editing.
   SwiftUI `TextEditor` is not sufficient for syntax styling, source ranges,
   preserved selection, and large files.

## 5. Delivery phases

### Phase 0 — public foundation

Work:

- complete and commit the OpenPane rename;
- correct prototype documentation and remove feature overclaims;
- add the MIT license, contribution/security policies, and clean-room rule;
- add reproducible `.app` packaging;
- add macOS 26 CI, tagged prereleases, checksums, and build provenance;
- publish `dburkhardt/OpenPane` as a public repository;
- create a clearly labeled `v0.0.1` prototype prerelease.

Exit criteria:

- the tracked tree contains no build products, credentials, or stale branding;
- build and tests pass from a fresh checkout;
- CI produces an Apple Silicon `.app` archive;
- the README says plainly that the app is a prototype;
- the release notes state that the preview is ad-hoc signed and not notarized.

### Phase 1 — native application foundation

Work:

- create the Xcode workspace, app target, shared packages, and test targets;
- choose `DocumentGroup` versus `NSDocument` through a focused file-coordination
  spike;
- add bundle metadata, icon, Markdown document types, app sandbox, hardened
  runtime, and minimal entitlements;
- make Reader the only default mode and add explicit Edit/Done;
- establish design tokens for typography, spacing, width, color, and motion;
- add Developer ID signing and notarization when credentials are available.

Exit criteria:

- double-clicking `OpenPane.app` launches it;
- Finder **Open With → OpenPane** opens supported Markdown files;
- no source editor appears until the user chooses Edit;
- a clean macOS 26 machine accepts the signed/notarized build;
- tagged builds are reproducible through CI.

Planning range: 3–5 focused days.

### Phase 2 — faithful and secure renderer

Work:

- adopt and pin a CommonMark/GFM parser;
- add stable semantic IDs and source ranges;
- render tables, nested/ordered/task lists, footnotes, alerts, links, local
  images, and safe raw HTML;
- add syntax highlighting with an intentionally supported grammar set;
- bundle Mermaid and math renderers offline;
- add automatic bounded HTTPS image loading, cache, placeholders, retry, and
  privacy control;
- implement responsive table/code overflow and polished light/dark editorial
  styles;
- build conformance fixtures and visual golden tests.

Exit criteria:

- representative GitHub READMEs and agent-generated documents render without
  meaningful structural loss;
- app, Quick Look semantic output, and HTML export agree on fixtures;
- narrow windows preserve usable tables and code;
- Mermaid never loads network scripts;
- hostile HTML cannot execute code, navigate, read files, or retain unsafe
  attributes/schemes;
- broken and oversized resources fail gracefully.

Planning range: 2–3 weeks.

### Phase 3 — complete reader and Quick Look

Work:

- add a Quick Look extension sharing `MarkdownEngine` and `RenderKit`;
- add quiet external-change reconciliation and semantic scroll preservation;
- add native find with count and highlights;
- finish outline navigation, link routing, recent documents, restored
  positions, tabs/windows, zoom, and reading-width controls;
- make the default window document-only and keyboard complete;
- complete accessibility semantics for headings, links, images, tables, and
  code.

Exit criteria:

- Spacebar in Finder previews supported Markdown through OpenPane;
- external writes appear after debounce without focus theft or scroll jumps;
- outline, find, copy, links, and restoration work by keyboard;
- a representative 1 MB document reaches meaningful first render within one
  second on the baseline supported Mac;
- a 100 KB Quick Look fixture renders within 500 ms after extension startup;
- VoiceOver exposes meaningful document order and structure.

Release gate: `v0.5` complete-reader beta.  
Planning range: 2–3 weeks.

### Phase 4 — explicit editing and quick fixes

Work:

- replace `TextEditor` with a selection-preserving TextKit 2 source editor;
- implement Edit/Done, save, undo/redo, revert, and external-conflict UI;
- synchronize source and preview positions;
- add formatting commands, task toggling, link/image insertion, paste/drop;
- add visual table row/column operations;
- add Mermaid source overlay with validation;
- add rendered-block quick fixes only where round-tripping is predictable.

Exit criteria:

- reading never changes a file;
- entering and leaving Edit preserves the corresponding document location;
- every edit is undoable;
- concurrent external edits produce an explicit compare/reload/keep choice;
- table and Mermaid edits never rewrite unrelated source.

Planning range: 3–5 weeks.

### Phase 5 — proofreading and publishing

Work:

- implement source-mapped repetition, sentence-length, passive-voice,
  readability, and jargon rules;
- add dictionaries, ignores, profiles, statistics, and issue navigation;
- add bounded link/image validation;
- produce print-quality PDF and standalone HTML;
- add themes, custom CSS, export profiles, and batch export;
- add validated DOCX and EPUB export;
- gate custom processors behind an out-of-process, explicitly permissioned
  design;
- keep Scrivener and tracked-change ingestion as research until testable
  contracts exist.

Exit criteria:

- every proofreading issue navigates to the exact source range;
- core proofreading remains completely offline;
- HTML/PDF match reader fixtures within documented platform differences;
- DOCX/EPUB pass structural validation and representative visual review;
- no processor ships without scoped file/network permissions.

Planning range: 4–8 weeks.

### Phase 6 — stable release hardening

Work:

- complete accessibility audit and keyboard coverage;
- fuzz malformed Markdown, HTML, SVG, URLs, and image inputs;
- profile large files, memory, leaks, parse/render latency, and scrolling;
- audit dependencies and licenses; produce an SBOM;
- add optional Sparkle updates or document a manual-update policy;
- publish a Homebrew cask after stable artifact URLs exist;
- complete privacy, clean-room, help, and localization-readiness reviews.

Exit criteria:

- no known critical/high security findings;
- fixed performance budgets have no unresolved regressions;
- the app remains useful with all networking disabled;
- signed, notarized, stapled builds install and update successfully;
- release assets include ZIP/DMG, SHA-256 checksums, SBOM, provenance, and
  release notes.

Release gate: OpenPane 1.0 after complete-reader hardening; OpenPane 2.0 after
the editing/publishing scope meets its gates.

## 6. Test strategy

| Layer | Required coverage |
|---|---|
| Unit | Parser adapter, source ranges, stable IDs, sanitizer, URL policy, cache, proofreader, exporters |
| Conformance | Official CommonMark/GFM cases plus OpenPane extension fixtures |
| Visual | Light/dark, window widths, text sizes, tables, code, Mermaid, images, HTML |
| Integration | File coordination, external writes, conflicts, position restore, export |
| Extension | Quick Look cold/warm lifecycle, latency, cancellation, resource failure |
| UI | Finder open, Edit/Done, keyboard navigation, find, save/revert, settings |
| Security | Hostile HTML/SVG, malformed Markdown, redirects, private URLs, oversized/decompression-bomb images |
| Performance | Parse, first render, reload, scrolling, memory, Quick Look startup |
| Release | Signature, notarization, stapling, first launch, associations, update path |

No phase is complete merely because its UI exists. Its acceptance fixtures,
security cases, accessibility behavior, and performance budget must pass.

## 7. CI/CD and release design

### Continuous integration

- Use GitHub's Apple Silicon `macos-26` runner.
- On every pull request and `main` push: build, run tests, package the app,
  validate the plist/signature/architecture/deployment target, verify the
  checksum, and upload a short-lived artifact.
- Give CI only `contents: read`.
- Cancel superseded branch runs.
- Keep GitHub Actions dependencies on Dependabot and move to immutable commit
  pins before stable releases.

### Tagged releases

- A protected `v*` tag runs tests and the same checked-in packaging script.
- Derive the marketing version from the tag and build number from CI.
- Produce `OpenPane-<version>-macos-arm64.zip`, `SHA256SUMS`, and GitHub build
  provenance.
- Create the GitHub release only after validation and attestation succeed.
- Keep early ad-hoc-signed builds marked as prereleases.

### Production distribution

Before calling a download stable:

- import the Developer ID certificate into an ephemeral CI keychain;
- sign with hardened runtime and timestamp;
- submit through `notarytool`, wait for success, and staple the ticket;
- re-archive the stapled app, recompute checksums, and then publish;
- keep signing/notarization secrets in a protected release environment;
- never expose signing secrets to fork pull requests.

## 8. Security and privacy boundary

- App sandbox and hardened runtime begin with the real app target.
- No document-supplied JavaScript executes.
- Sanitization strips scripts, frames, objects, event handlers, unsafe CSS, and
  dangerous URL schemes.
- Remote requests send no cookies, credentials, or referrer and have strict
  redirect, byte, dimension, concurrency, and cache limits.
- Credential-bearing URLs are rejected. HTTP, localhost/private-network URLs,
  SVG, and Quick Look networking require recorded policy decisions.
- Links never navigate the document view silently.
- Core behavior requires no account, telemetry, or network.
- Future processors execute out of process with explicit scoped permissions.

## 9. Architecture decisions to record

Create ADRs before the affected phase:

1. `DocumentGroup` versus `NSDocument`
2. CommonMark/GFM parser and extension policy
3. Native/WebKit rendering boundary
4. Remote image behavior in Quick Look
5. HTTP and private-network resource policy
6. Raw HTML and SVG allowlists
7. Syntax-highlighting engine and grammar licenses
8. Sparkle versus manual GitHub updates
9. Public-history treatment of the original prototype name
10. Signing/notarization and protected-release environment
11. Exact OpenPane 1.0 versus 2.0 boundary

## 10. Highest risks

- Rendered editing is substantially harder than source editing. Reader quality
  must come first.
- Quick Look has a tighter lifecycle and resource budget; prototype it early.
- Hybrid native/web rendering can drift; the shared semantic tree and fixtures
  are mandatory.
- Remote resources and HTML create the largest privacy/security surface.
- DOCX/EPUB fidelity and processors are open-ended; keep them behind explicit
  gates.
- Clean-room parity and dependency-license audits must remain visible in every
  public milestone.

## 11. Planning range

For one focused developer:

- **6–9 weeks:** strong complete-reader beta;
- **roughly 3 months:** hardened OpenPane 1.0 reader;
- **4–6 months total:** broader editing, proofreading, and publishing suite.

These are sequencing estimates, not release promises. Each phase exits on
measured acceptance criteria, not elapsed time.
