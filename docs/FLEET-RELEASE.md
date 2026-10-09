# Release completion

The source tree contains the native telemetry schema and release hooks. To ship a notarized macOS build, configure a macOS GitHub Actions runner with Apple Developer ID Application credentials, an App Store Connect API key or notarytool profile, and the Team ID. Keep those values in GitHub encrypted secrets.

A Homebrew formula can then point at the signed/notarized release archive and SHA-256. These two release steps cannot be executed or verified without the organization's Apple signing credentials and a macOS environment.
