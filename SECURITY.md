# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do
not open a public issue for a suspected vulnerability.

Include:

- the affected commit or release;
- a minimal reproduction;
- expected and observed behavior;
- potential file, network, privacy, or code-execution impact.

## Supported versions

OpenPane has no stable release yet. Security fixes target the latest preview
and `main` on a best-effort basis until version 1.0.

## Security boundary

OpenPane treats every document and remote resource as untrusted. Its target
design prohibits document-supplied JavaScript, sanitizes raw HTML, bounds
remote resources, preserves sandboxing, and keeps future processors out of
process with explicit permissions.
