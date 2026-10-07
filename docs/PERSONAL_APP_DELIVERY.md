# Personal app delivery

The sufficient outcome is a locally signed macOS app from this fork, with the
existing Claude/Codex monitoring and owner-controlled feedback and updates.
Public release/notarization and account login are separate live steps.

Required fixes and gates:

- Replace plaintext credential fallback with verified, recoverable secure
  persistence. Preserve legacy data until secure migration succeeds.
- Treat profile names and saved statusline settings as data, never shell code.
- Make automatic Claude OAuth polling a read-only usage request. Do not generate
  a model response as a side effect of polling.
- Restrict credential-bearing Codex requests to official ChatGPT hosts over
  HTTPS and refuse redirects. Let Codex own refresh of its shared login file;
  continue refreshing manually managed profiles separately.
- Resolve the introduced CI failure with a reproduced cause, then run focused
  tests and final Debug/Release builds on the handed-off commit.
- Sign a local app with the available Apple Development identity and verify its
  complete bundle. This does not confer Developer ID notarization.

Tests use synthetic credentials and temporary stores only. Do not launch the
app, alter existing installations, or connect live accounts during validation.
Stop once the source, passing validation, signed local app, and exact remaining
live verification requirements are handed off.
