# GreekInk

Personal iPad keyboard: handwrite Greek with the Apple Pencil and get text in any app.
Recognition is on-device with Google ML Kit Digital Ink. Personal use only, no App Store,
signed with a free Apple "Personal Team" (so it expires every 7 days, see below).

Status: **Phase 0** (project skeleton, empty keyboard, App Group test).

## What you need

- Mac with Xcode 27.2 or newer, CocoaPods (`pod --version`).
- iPad with Apple Pencil, iPadOS 17 or newer. A USB cable for the first install.
- An Apple ID signed in to Xcode (Xcode → Settings → Accounts). No paid membership.

## One-time setup on the Mac

```sh
git clone git@github.com:altany/apple-greek-handwriting.git
cd apple-greek-handwriting

# 1. Signing config (git-ignored). Put your Personal Team ID in it.
cp Local.xcconfig.example Local.xcconfig

# 2. XcodeGen, kept inside the project (tools/ is git-ignored, nothing global).
mkdir -p tools && curl -sSL -o tools/xcodegen.zip \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip \
  && unzip -q tools/xcodegen.zip -d tools && rm tools/xcodegen.zip

# 3. Generate the Xcode project, then install pods.
tools/xcodegen/bin/xcodegen generate
pod install            # from Phase 1 on; creates GreekInk.xcworkspace
```

`project.yml` is the source of truth for the Xcode project. After changing it, run
`tools/xcodegen/bin/xcodegen generate && pod install` again.

Where to find the Personal Team ID: Xcode → Settings → Accounts → your Apple ID →
the team named "Your Name (Personal Team)". Or open the project, Signing & Capabilities,
pick that team, and copy the ID that Xcode writes next to it.

## Build and install on the iPad

Plug in the iPad, unlock it, tap **Trust** when asked. Then the short way:

```sh
scripts/install-ipad.sh        # build + install + launch; auto-detects the iPad
```

Or by hand:

```sh
# Find the iPad's identifier
xcrun devicectl list devices

# Build (creates certificate + profiles on first run) and install
xcodebuild -workspace GreekInk.xcworkspace -scheme GreekInk \
  -destination 'id=<IPAD-UDID>' -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <IPAD-UDID> \
  build/DerivedData/Build/Products/Debug-iphoneos/GreekInk.app
```

Before `pod install` exists (Phase 0), use `-project GreekInk.xcodeproj` instead of
`-workspace GreekInk.xcworkspace`.

Or in Xcode: open `GreekInk.xcworkspace`, select the iPad as the run destination, press Run.

## One-time setup on the iPad

1. **Developer Mode.** After the first install attempt the iPad shows
   Settings → Privacy & Security → Developer Mode. Turn it on, restart, confirm.
2. **Trust the developer profile.** Settings → General → VPN & Device Management →
   under "Developer App" tap your Apple ID → Trust. Until then the app icon is greyed out.
3. **Enable the keyboard.** Settings → General → Keyboard → Keyboards → Add New Keyboard… →
   under Third-Party Keyboards pick **GreekInk**.
4. **Use it.** In any text field, hold the 🌐 key and pick GreekInk.
5. **Full Access** (later phases, only if the keyboard must download the model itself):
   Settings → General → Keyboard → Keyboards → GreekInk → Allow Full Access.

## Every 7 days

A free Personal Team signs apps that stop launching after 7 days ("GreekInk is no longer
available"). Nothing is lost: plug in the iPad and run the build + install commands above
again. Keyboard settings stay enabled. Other free-team limits: at most 3 such apps on the
iPad at once, and about 10 new App IDs per week.

## Project layout

```
project.yml            XcodeGen spec (targets, Info.plist, entitlements)
Local.xcconfig         Team ID + bundle prefix (git-ignored; copy from .example)
GreekInk/              Host app (SwiftUI): Write tab (prototype canvas, candidates,
                       misread log), Setup tab (model download, App Group test, memory)
GreekInkKeyboard/      Keyboard extension (UIKit); still the Phase 0 test keyboard
Shared/                Compiled into both targets: ink canvas, ML Kit wrapper, App Group, memory
scripts/install-ipad.sh  Build, install and launch on the iPad
Podfile, Podfile.lock  ML Kit via CocoaPods
tools/                 XcodeGen binary (git-ignored)
CLAUDE.md              Decisions, status, findings, next step (read first)
```

## Troubleshooting

- *"Signing requires a development team"*: `Local.xcconfig` is missing or has the placeholder ID.
- *"Untrusted Developer"* on the iPad: step 2 above.
- *Keyboard does not appear in the list*: the app must be installed and launched once;
  then check Settings → General → Keyboard → Keyboards.
- *Keyboard disappears mid-use*: it was killed for memory. See CLAUDE.md, risk 1.
- *Simulator build fails on Apple Silicon*: expected, ML Kit excludes arm64 simulator. Use the iPad.
