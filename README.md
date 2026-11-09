# GreekInk

An iPad keyboard for handwriting Greek with the Apple Pencil (or a finger), in any app.

Apple's Scribble turns handwriting into text in any text field, but it has no Greek and no
API to add a language. GreekInk is a custom keyboard extension instead: you write on a strip
at the bottom of the screen, and the words are inserted where the cursor is. Recognition runs
on the device with [Google ML Kit Digital Ink Recognition](https://developers.google.com/ml-kit/vision/digital-ink-recognition),
which has Greek (`el`) and English (`en`) models. Your handwriting and your text never leave
the iPad. The keyboard has no network at all. The app goes online only to download the model,
and ML Kit sends Google basic usage metrics from it ([ML Kit terms](https://developers.google.com/ml-kit/terms)).

It is a personal project, not on the App Store. It is signed with a free Apple "Personal Team",
so an install runs for 7 days and then needs a re-install from the Mac.

## How it works

- **Write, pause, done.** After an 800 ms pause the ink is recognised, the best candidate is
  inserted with an automatic space, and the alternatives appear in a bar above the strip.
  Tap one to swap it in. Accents (τόνος), dialytika and capitals come out right.
- **ΕΛ / EN key** switches between the Greek and the English model. The Greek model reads many
  Latin words by itself (e.g. "Apple"); for the rest, switch.
- **Scratch out.** A quick zigzag on the strip erases the ink there; on an empty strip it
  deletes the last word. (ML Kit's iOS SDK has no gesture model, so this is a small geometric
  check in `GreekInkKeyboard/ScribbleDetector.swift`.)
- **Punctuation and numbers.** A row of keys above the strip: . , ; · ! ? : ' " ( ) -.
  The 123 key swaps it to digits and makes handwriting prefer digits too.
- **Context.** The last 20 characters before the cursor are passed to ML Kit, which helps it
  pick the right word.
- **No Full Access needed.** A keyboard without Full Access has no network, so it cannot
  download the model. The app downloads it and copies ML Kit's model folder into the shared
  App Group container. The keyboard copies that into its own container before ML Kit starts.
  ML Kit names some files after the app's bundle ID, so the keyboard adds renamed copies.
  On APFS the copy is a clone: about 13 ms.
- **Small.** With the Greek model loaded the keyboard uses about 9 MB of memory (the model is
  memory-mapped); the limit for keyboards on an iPad Air M1 is about 90 MB. A word takes
  30–100 ms to recognise.
- **Palm-friendly canvas.** Pencil touches win over a resting palm, and touches wider than a
  fingertip are ignored.

The host app has a **Write** tab (a full-screen test canvas with the top 5 candidates and a
misread log) and a **Setup** tab (enable steps, model downloads, the copy for the keyboard).

## What you need

- Mac with Xcode 27.2 or newer and CocoaPods (`pod --version`). ML Kit has no Swift Package.
- iPad with iPadOS 17 or newer. A USB cable for the first install.
- An Apple ID signed in to Xcode (Xcode → Settings → Accounts). No paid membership.

## One-time setup on the Mac

```sh
git clone https://github.com/altany/apple-greek-handwriting.git
cd apple-greek-handwriting

# 1. Signing config (git-ignored): your Personal Team ID and your own bundle ID prefix.
cp Local.xcconfig.example Local.xcconfig

# 2. XcodeGen, kept inside the project (tools/ is git-ignored, nothing global).
mkdir -p tools && curl -sSL -o tools/xcodegen.zip \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip \
  && unzip -q tools/xcodegen.zip -d tools && rm tools/xcodegen.zip

# 3. Generate the Xcode project, then install pods (creates GreekInk.xcworkspace).
tools/xcodegen/bin/xcodegen generate && pod install
```

`project.yml` is the source of truth for the Xcode project. After changing it (or
`Local.xcconfig`), run `tools/xcodegen/bin/xcodegen generate && pod install` again.

Where to find the Personal Team ID: Xcode → Settings → Accounts → your Apple ID → the team
named "Your Name (Personal Team)". Or open the project, Signing & Capabilities, pick that
team, and copy the ID Xcode writes into the project.

## Build and install on the iPad

The script `scripts/install-ipad.sh` does everything: builds the app and the keyboard with
your Personal Team, installs them on the iPad and opens the app.

1. Connect the iPad to the Mac with a USB cable.
2. Unlock the iPad. The first time, tap **Trust** on the iPad when it asks about this Mac.
3. In the project folder on the Mac, run:

   ```sh
   scripts/install-ipad.sh
   ```

   It finds the iPad by itself. With several devices connected, pass the one you want:
   `scripts/install-ipad.sh <device-id>` (ids from `xcrun devicectl list devices`).
4. It prints `** BUILD SUCCEEDED **`, then "App installed", then "Launched application".
   The first build takes a few minutes (ML Kit is large); later ones are faster.

If it ends with **"Locked"**, the install worked but the iPad was locked, so it couldn't
open the app: unlock it and open GreekInk yourself. If the app icon is greyed out or the
iPad says "Untrusted Developer", see the one-time setup below.

Or open `GreekInk.xcworkspace` in Xcode, pick the iPad as the run destination and press Run.

## One-time setup on the iPad

1. **Developer Mode.** After the first install attempt the iPad shows
   Settings → Privacy & Security → Developer Mode. Turn it on, restart, confirm.
2. **Trust the developer profile.** Settings → General → VPN & Device Management →
   under "Developer App" tap your Apple ID → Trust.
3. **Download the model.** Open GreekInk, Setup tab, download Ελληνικά (and English if you
   want it). The app copies it for the keyboard automatically.
4. **Enable the keyboard.** Settings → General → Keyboard → Keyboards → Add New Keyboard… →
   under Third-Party Keyboards pick **GreekInk**. Leave "Allow Full Access" off.
5. **Use it.** In any text field, hold the 🌐 key and pick GreekInk.

## Every 7 days

A free Personal Team signs apps that stop launching after 7 days ("GreekInk is no longer
available"). Nothing is lost, not even the keyboard settings or the downloaded model: plug in
the iPad, unlock it and run `scripts/install-ipad.sh` again (steps above).
Other free-team limits: at most 3 such apps on a device, about 10 new App IDs per week.

## Project layout

```
project.yml              XcodeGen spec (targets, Info.plist, entitlements)
Local.xcconfig           Team ID + bundle prefix (git-ignored; copy from .example)
GreekInk/                Host app (SwiftUI): Write tab, Setup tab, model copy for the keyboard
GreekInkKeyboard/        Keyboard extension (UIKit): writing strip, candidate bar, keys
Shared/                  Compiled into both: ink canvas, ML Kit wrapper, model sharing,
                         App Group, memory numbers, diagnostics log
scripts/install-ipad.sh  Build, install and launch on the iPad
scripts/make-icon.swift  Draws the app icon (swift scripts/make-icon.swift <out.png>)
Podfile, Podfile.lock    ML Kit via CocoaPods
CLAUDE.md                Working notes: decisions, measurements, findings, phase status
docs/                    Blog brief, App Store investigation
```

## Troubleshooting

- *"Signing requires a development team"*: `Local.xcconfig` is missing or still has the placeholder.
- *"Untrusted Developer"* on the iPad: step 2 above.
- *Keyboard says "model not available"*: open GreekInk once with the model downloaded
  (Setup tab shows "Shared copy"), then switch to the keyboard again.
- *Simulator build fails on Apple Silicon*: expected, ML Kit excludes the arm64 simulator.
  Use a real iPad.

## Using it for another language

Greek isn't the only language missing from Scribble. ML Kit has handwriting models for
[over 300 languages](https://developers.google.com/ml-kit/vision/digital-ink-recognition/base-models),
and nothing in the recognition, the model sharing or the scratch-out depends on Greek. To switch
the keyboard to another language, change these:

- `Shared/Recognition/InkLanguage.swift`: the ML Kit tag (`case greek = "el"`, e.g. `"ru"`,
  `"bg"`, `"uk"`), its `label` (shown on the Setup tab), and the default in `saved`.
- `GreekInkKeyboard/KeyboardViewController.swift`:
  - the language key: its title in `updateLanguageKey()` (`"ΕΛ"` / `"EN"`) and the switch
    between the two languages in `languageTapped()`;
  - `punctuation`, the symbol row (Greek has `;` as its question mark and `·`);
  - `needsSpace(before:word:)`, which decides when to add the automatic space (it knows the
    Greek question mark and ano teleia).
- `GreekInkKeyboard/NumberMode.swift`: `lookalikes`, the letters that number mode turns into
  digits (Greek Ο, ι, Ζ, Τ, Β next to the Latin ones). Add the look-alikes of your script.
- `project.yml`: `PrimaryLanguage: el` for the keyboard (the language iPadOS files it under), and,
  if you like, the app name and bundle IDs. Then run
  `tools/xcodegen/bin/xcodegen generate && pod install`.

Then download the new model on the Setup tab; the copy for the keyboard happens by itself.

That should be enough for languages written left to right with spaces between words, such as
Russian or Bulgarian (only Greek and English have been tried). Two kinds need more work and are
untested: right-to-left scripts such as Arabic and Hebrew (at least `PrefersRightToLeft` in
`project.yml`), and languages without spaces such as Chinese, Japanese or Thai (the automatic
space has to go).

## How it was built

Built with [Claude Code](https://claude.com/claude-code) in phases (setup, prototype app,
keyboard, polish). `CLAUDE.md` holds the running notes: what was decided and why, what was
measured on the device, and what went wrong along the way.

## Licence

GreekInk's own code is MIT, see `LICENSE`. Google ML Kit, which it downloads and links, comes
under [Google's own terms](https://developers.google.com/ml-kit/terms).
