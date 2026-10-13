# Widgets and Shortcuts

The native app ships a WidgetKit widget and two App Intents. They are read-only and show only what the app has already measured.

## Widget

**System** (small and medium): CPU and memory rings; the medium size adds the three busiest apps and an alert count. It says "Simulated" for demo data and "Vytrix is not running" with the age of the reading when the app has not published for two minutes. It never shows an old number as current. With no reading yet it says to open Vytrix.

Add it from Edit Widgets on the desktop or in Notification Center, under Vytrix.

## Shortcuts and Spotlight

| Intent | Says |
|---|---|
| **What is using my CPU?** | `CPU is at 42%. Busiest: Chrome 18%, Xcode 9% and node 4%.` |
| **How is my Mac doing?** | `mac-01: CPU 42%, memory 63%, disk 70% full, no active alerts.` |

Both return text only, are available in Shortcuts, and are registered as App Shortcuts, so Spotlight and Siri can offer them. They read the last reading the app published, and say when it is old, missing or simulated instead of guessing. Neither acts on the host.

## How the data flows

The app writes `widget.json` (totals, the five busiest apps' names and CPU, an alert count; no tokens, no process IDs or paths) about every five seconds, and asks WidgetKit to reload at most every 30 seconds. The widget extension is sandboxed, so it reads from its own container, `~/Library/Containers/dev.zyvor.vytrix.widgets/`. The app is not sandboxed, so it writes there directly, and only once that container exists (the first time macOS runs the widget); it never creates it.

An App Group would be the conventional channel, but it needs a Developer team identity and this repository's builds are ad-hoc signed. With a signing team, `WidgetStore` is the single place to change.

## Building

```bash
brew install xcodegen
./scripts/build-native-widgets.sh   # native/build/Vytrix.app with the widget and App Intents
```

`scripts/build-native.sh` still builds the app without them and needs only the command line tools. The release workflow builds with widgets and, if that build fails, packages the plain app and prints a warning.

## What is and is not verified

Verified: the Xcode build embeds a sandboxed, signed widget extension and App Intents metadata; the extension registers with `pluginkit`; the app writes the data file into the widget container; the intents' answers, the file round trip and staleness are covered by `scripts/test-native-logic.sh`; and the widget views were rendered at both sizes.

Not verified: the widget inside the macOS widget gallery and on the desktop, Spotlight and Siri phrases, and anything on macOS 26. The widget's own process has not been observed running.
