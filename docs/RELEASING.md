# Releasing OpenPane

OpenPane's public tag workflow is fail-closed: it cannot publish a GitHub
release unless Apple accepts the exact Developer ID-signed app being packaged.
Ordinary branch and pull-request artifacts remain ad-hoc developer previews and
never receive release credentials.

## One-time GitHub setup

The `release` environment is restricted to tags matching `v*`. Configure these
environment secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | Base64-encoded Developer ID Application certificate and private key |
| `DEVELOPER_ID_CERT_PASSWORD` | Password protecting the P12 export |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Developer team ID (`J3Q35LXP2V`) |
| `APPLE_APP_PASSWORD` | App-specific password for the Apple ID |

Never paste these values into an issue, workflow, release note, or terminal log.
Repository secrets cannot be read back after they are stored.

## Release sequence

1. Confirm `main` is clean and CI passes.
2. Update `CHANGELOG.md`.
3. Create a new annotated tag. Never move or recreate a published tag.
4. Push the tag.
5. Wait for the `Build signed and notarized prerelease` job.

The workflow:

1. imports the P12 into an ephemeral keychain;
2. signs `OpenPane.app` with Developer ID Application, Hardened Runtime, and a
   secure timestamp;
3. submits a temporary ZIP to Apple's notary service and requires `Accepted`;
4. saves the non-secret notarization response and log as a workflow artifact;
5. staples and validates the ticket;
6. requires Gatekeeper acceptance;
7. creates a new ZIP from the stapled app;
8. checksums and attests that final ZIP; and
9. publishes the GitHub prerelease.

`v0.0.1` is the immutable historical ad-hoc prototype. The first release using
this pipeline is `v0.0.2`.

## Verify the download

After downloading the release ZIP and `SHA256SUMS`, run:

```sh
shasum -a 256 -c SHA256SUMS
ditto -x -k OpenPane-0.0.2-macos-arm64.zip verified
codesign --verify --deep --strict --verbose=3 verified/OpenPane.app
xcrun stapler validate -v verified/OpenPane.app
spctl --assess --type execute --verbose=4 verified/OpenPane.app
```

The signature details must show `Developer ID Application`, team
`J3Q35LXP2V`, Hardened Runtime, and a secure `Timestamp`. Gatekeeper must report
the app as accepted notarized Developer ID software.
