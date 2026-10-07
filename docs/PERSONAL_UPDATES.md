# Personal updates for this fork

The personal app's update feed is
`https://0xysh.github.io/claude-usage-tracker/appcast.xml`, with signed archives
under `https://0xysh.github.io/claude-usage-tracker/releases/`. The appcast workflow
derives these publishing URLs from the current repository owner and name. It
publishes only this repository's releases and retains their history on `gh-pages`.

## Before the first personal release

1. The app must bundle our own Ed25519 public key as `SUPublicEDKey` in
   `Claude Usage/Resources/Info.plist`. Store its matching private key securely as
   this repository's `SPARKLE_PRIVATE_KEY` Actions secret. Never commit, log, or
   copy that private key into the app. Keep a secure backup: losing it prevents
   future updates from being accepted by installations trusting its public key.
2. Configure our own Apple signing/notarization credentials for the release
   workflow: `DEVELOPER_CERTIFICATE_BASE64`, `CERTIFICATE_PASSWORD`, `APPLE_ID`,
   `APPLE_ID_PASSWORD`, and `TEAM_ID`. The Developer ID certificate must belong
   to us, and the app's signing configuration must use our team. These are
   separate from the Sparkle signing key.
3. Enable this fork's GitHub Actions. In **Settings → Pages → Build and
   deployment**, set **Source** to **GitHub Actions**. Confirm any `github-pages`
   environment protection rules permit the release workflow's tags and manual
   appcast runs from the default branch. The workflow does not enable Pages or
   change repository settings automatically.
4. Publish a signed, notarized personal release using a version tag such as
   `v3.3.1`. Include `Claude-Usage.zip` and `Claude-Usage.zip.sha256`. Set a higher
   `CFBundleVersion` than the installed personal app for subsequent updates.
   Run **Generate Appcast** for that tag if it was not dispatched automatically.
   The workflow verifies the release checksum, code signature, and stapled
   notarization ticket before signing the feed. It also rejects a release whose
   embedded update URL or public key differs from this fork's configuration.

The first personal build must be installed explicitly. An upstream installation
trusts the upstream public key, so changing URLs or signing a release with our
key does not migrate that trust automatically. Our build must contain both our
public key and our feed URL before future personal updates can work.

The local signing setup stores the private key in the ignored
`.private/sparkle-private-key` file, with owner-only permissions (0600) inside an
owner-only directory (0700). Its public counterpart is
`.private/sparkle-public-key`; the public value belongs in the app's Info.plist.
When ready to configure the repository secret, send the private file directly to
GitHub without displaying its contents:

```sh
gh secret set SPARKLE_PRIVATE_KEY --repo 0xysh/claude-usage-tracker < .private/sparkle-private-key
```

This documentation does not upload the key or publish a release. Keep the private
file and a secure backup out of version control.

## Publishing behavior

The workflow creates a missing `gh-pages` branch as an orphan branch in its
temporary checkout, or restores the existing branch. It pushes only to
`refs/heads/gh-pages`, without force pushing or changing `main`. It uses the
repository's `GITHUB_TOKEN` with `contents: write`, then explicitly uploads and
deploys the Pages artifact with `pages: write` and `id-token: write`. This avoids
an external publishing token. A `GITHUB_TOKEN` push alone does not trigger a
branch-based Pages build, which is why the explicit deployment is required.

Sparkle tools are pinned to 2.10.0 and their archive is checked before extraction
against the official release asset's SHA-256:
`c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`.
The private Ed25519 key is passed to `generate_appcast` through stdin, and the
tools are kept outside the published directory. Previous versioned ZIPs remain
available for delta generation and updates from older personal installations.

## Optional Homebrew tap

Homebrew publishing is skipped unless the repository variable
`HOMEBREW_TAP_REPOSITORY` names an existing tap owned by the same account as this
fork, in `owner/repository` form. Configure `HOMEBREW_TAP_TOKEN` with write access
to that tap and provide its `Casks/claude-usage-tracker.rb`. The workflow updates
its version, SHA-256, and download URL to this fork's release. It refuses a tap
owned by another account and never defaults to the upstream author's tap.
No tap repository is created automatically.

## Verification references

- [Official Sparkle 2.10.0 release and asset metadata](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)
- [GitHub Pages custom workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [GitHub Pages publishing sources and GITHUB_TOKEN limitation](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
