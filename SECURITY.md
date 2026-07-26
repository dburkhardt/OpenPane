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

OpenPane treats every file and workspace as untrusted. It runs in the App
Sandbox, never executes opened content, never fetches remote Markdown resources,
does not recursively follow directory symlinks, and never rewrites binary
originals through a decoded text view. Coordinated writes require an explicit
save and detect external changes before replacing a file.
