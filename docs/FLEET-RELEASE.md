# Release completion

See also [RELEASE.md](RELEASE.md) for what has and has not been verified.

The source tree contains the native telemetry schema and release hooks. To ship a notarized macOS build, configure a macOS GitHub Actions runner with Apple Developer ID Application credentials, an App Store Connect API key or notarytool profile, and the Team ID. Keep those values in GitHub encrypted secrets.

Until then the DMG is signed by hand: the v0.3.0 `Vytrix-0.3.0.dmg` (Developer ID signed, not notarized) and its `.sha256` are attached to the [v0.3.0 release](https://github.com/zyvorai/zyvor-vytrix/releases/tag/v0.3.0) (steps in [RELEASE.md](RELEASE.md#release-artifacts)).

A Homebrew formula can then point at the signed/notarized release archive and SHA-256. These two release steps cannot be executed or verified without the organization's Apple signing credentials and a macOS environment.
