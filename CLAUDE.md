# GreekInk — Greek handwriting keyboard for iPad

Personal iPad keyboard: handwrite Greek with Apple Pencil, get text in any app.
Apple's Scribble has no Greek and no API to add one, so this is a custom keyboard.
Personal use only. No App Store.

## Status (end of 2026-11-05) — read this first
- Phase 0 and Phase 1 are DONE and accepted by the user. The prototype app works on the
  iPad: Pencil and finger writing, auto-recognition 600 ms after the last stroke, top-5
  candidates, Copy / Undo / Clear, el/en switch, model download status, misread log, and a
  Setup tab (App Group test, model storage report, memory). Everything is committed and pushed.
- NEXT: Phase 2 (keyboard MVP). The user has NOT yet said "go": ask, then do the risky part
  first, in this order.
  1. Model sharing. Host app copies ML Kit's model folder (path in Findings) into the App
     Group container; the keyboard points its own `Library/Application Support` at that copy
     (symlink, or whatever ML Kit accepts) and must pass `isModelDownloaded` AND a real
     recognition without Full Access. If ML Kit refuses (likely culprit: the MDD lock file in
     `Download/`), fall back to downloading with Full Access on, and tell the user plainly.
  2. Measure keyboard memory with the model loaded (`MemoryFootprint.summary()`; baseline was
     8.3 MB used / 81.7 MB headroom). Decide Plan B only on a measured number.
  3. Replace the Phase 0 `KeyboardViewController` with the real keyboard, reusing `Shared/`:
     `InkCanvasView` writing strip, candidate bar (3–5), space, backspace, return, globe
     (`handleInputModeList`), a Greek/Latin toggle key (switches el/en model), insert via
     `textDocumentProxy`, commit the top candidate after a pause or on tap, auto spaces,
     light/dark, ~300 pt height. Recognise per word/pause, not whole sentences.
  4. Host app Setup screen: enable-keyboard steps, model status, "copy model for keyboard".
- Decided along the way: the Greek/Latin toggle key is Phase 2. Running the `en` model as well
  and showing its top candidate as an extra chip is a Phase 3 experiment (measure memory first).
  Phase 4 stays optional: ask first, report cost and latency before building.
- The signed app and keyboard stop launching on 2026-11-12 (7-day profiles). Re-run
  `scripts/install-ipad.sh` with the iPad unlocked; nothing else is needed.
- Already set up on this Mac, do not ask for it again: `Local.xcconfig` holds the Personal
  Team ID and `BUNDLE_ID_PREFIX = com.tany4`; XcodeGen is in `tools/xcodegen/bin/`;
  CocoaPods works; the iPad is paired and trusted.

## How a test round works
- `scripts/install-ipad.sh` builds, installs and launches. Launch fails with "Locked" when the
  iPad has gone to sleep: the install still succeeded, ask the user to unlock it and open
  GreekInk.
- The user writes on the iPad and says "done". Then pull `Documents/diagnostics.log` and
  `Documents/misreads.json` with devicectl (command in Findings) instead of asking for pastes.
  After a crash, pull the system crash logs (.ips JSON) the same way.
- The user answers option questions through the dialog, usually with one word. Approvals given
  so far covered only what was asked (e.g. deleting Xcode DerivedData, not simulators or
  DeviceSupport). Disk on the Mac was tight: ~11 GB free after that cleanup.

## Code map
- `Shared/` (compiled into app AND keyboard): `Ink/InkStroke.swift` (point/stroke types),
  `Ink/InkCanvasView.swift` (UIKit canvas: strokes with timestamps, Pencil beats palm,
  palm-size filter, light/dark), `Recognition/InkRecognitionService.swift` (ML Kit wrapper:
  model download/delete/state, `recognize(_:language:preContext:writingArea:maxResults:)`),
  `Recognition/InkLanguage.swift` (el/en, saved in UserDefaults),
  `Recognition/ModelStorageInspector.swift`, `AppGroup.swift` (container, ping write/read),
  `MemoryFootprint.swift`.
- `GreekInk/` (host app, SwiftUI): `ContentView.swift` (Write/Setup tabs, owns the objects),
  `Prototype/` (PrototypeView + PrototypeViewModel, `InkCanvas` wrapper, `MisreadLog` →
  Documents/misreads.json, `DiagnosticsLog` → Documents/diagnostics.log),
  `Setup/SetupView.swift`.
- `GreekInkKeyboard/`: still the Phase 0 test keyboard (`KeyboardViewController.swift`,
  `InkTestView.swift`). Phase 2 replaces it.
- `project.yml` is the source of truth for targets and settings (regenerate after edits);
  `Podfile` pins ML Kit 9.0.0; `scripts/install-ipad.sh` builds, installs, launches.

## Who I'm working with
- Senior mobile engineer (12 years, mostly React Native + TypeScript). Explain
  iOS-native details briefly only when they matter. Short, plain explanations.
  No buzzwords.
- Small commits, push often.
- ASK FIRST before: anything touching the Apple account, certificates or
  provisioning; creating/changing GitHub repos; installing global tools.
- Build with `xcodebuild` yourself when possible. Say clearly when something must
  be done by hand in Xcode or on the iPad.
- If something is a real blocker, say so early.
- Work in phases (below). Stop at the end of each phase, show what works, wait
  for a go-ahead.

## Decisions (made)
- Native iOS app + custom keyboard extension, Swift. No React Native (a keyboard
  extension cannot afford its memory).
- Recognition: Google ML Kit Digital Ink Recognition, on-device. Text model
  `el` (Greek) and `en`. Gesture model `el-x-gesture` later. Input is strokes
  (x, y, t), not images. Model ~20MB, downloaded on first use.
- Optional later (Phase 4, ask first): "clean up" button via the Claude API.
- Bundle IDs: `com.tany4.greekink` (app), `com.tany4.greekink.keyboard`
  (keyboard). App Group: `group.com.tany4.greekink`.
- Signing: free "Personal Team" ONLY. The Apple ID is also on an employer team;
  never use it. Team ID lives in git-ignored `Local.xcconfig`
  (see `Local.xcconfig.example`), nowhere else.
- GitHub: private repo `apple-greek-handwriting` on the personal account `altany`.
- Project file is generated by XcodeGen from `project.yml` (binary in `tools/xcodegen/`,
  git-ignored, not a global install). After editing `project.yml`:
  `tools/xcodegen/bin/xcodegen generate && pod install`.
- CocoaPods only (ML Kit has no SPM). Commit `Podfile.lock`.
  CocoaPods trunk goes read-only on 2 Dec 2026; existing pods still install.

## Environment (checked 2026-11-05)
- Mac: macOS 26.6.2, Xcode 27.2 (build 27B52), iOS 27.2 SDK.
- CocoaPods 1.15.2 (asdf Ruby 3.4.5). Homebrew present. XcodeGen not global.
- iPad Air 5th gen (M1), iPadOS 27.0.1, Apple Pencil.
- ML Kit: pod `GoogleMLKit/DigitalInkRecognition` 9.0.0 → `MLKitDigitalInkRecognition`
  8.0.0. Min iOS 15.5. Podspec sets `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`
  for the pods AND the app targets, so no Apple Silicon simulator: test on the iPad.
- Free Personal Team limits: app expires after 7 days (re-install from Xcode),
  ~10 new App IDs per week, max 3 self-signed apps on the device at once.

## Known risks (verify, don't assume)
1. Memory [baseline measured, model-loaded number still missing]: limit ~90MB on the iPad
   Air M1 (see Findings), not 48–60MB. ML Kit model alone ~20MB in RAM. Measure on the real
   iPad as soon as the keyboard loads the model.
2. Network: without "Allow Full Access" a keyboard extension has no network and
   cannot download the model. Plan (a): host app downloads, shares via App Group.
   Plan (b): extension downloads with Full Access on. App Groups may not work on
   a free Personal Team. A keyboard without Full Access may only read (not
   write) the App Group container. ML Kit picks its own model folder. Test all.
   [App Groups on the Personal Team: VERIFIED. Keyboard read-only in the group: VERIFIED.
   ML Kit loading a model from a shared path: NOT TESTED, first task of Phase 2.]
3. ML Kit may not be extension-safe (APPLICATION_EXTENSION_API_ONLY). [Links and builds:
   VERIFIED. Recognition running inside the extension: NOT TESTED.]
4. Apple Pencil in a keyboard extension: confirm touches arrive with
   `UITouch.TouchType.pencil` and drawing is smooth. Support finger too. [VERIFIED in the
   Phase 0 keyboard and in the app; palm handling lives in InkCanvasView, see Findings.]
5. Greek accuracy: accents (τόνοι), dialytika, final sigma (ς), capitals.
   Only the user can judge, by testing. Keep a log of misreads. [Ongoing: long sentences
   good, 2 misreads logged, both single letters. Final sigma still untested.]

Never guess ML Kit API names. Check the official docs
(https://developers.google.com/ml-kit/vision/digital-ink-recognition/ios) and
the official sample (github.com/googlesamples/mlkit, `ios/quickstarts/digitalinkrecognition`).

## Phases
- Phase 0 (setup) — DONE: project + keyboard target, CocoaPods, .gitignore, git, GitHub,
  CLAUDE.md, README.md. First device test: empty app + empty keyboard + App
  Group, to catch signing problems early.
- Phase 1 — DONE: prototype app only. Canvas, top-5 candidates, Copy, Clear, el/en
  switch. Auto-recognise ~600ms after the last stroke + manual button. Model
  download with visible status. Log misreads.
- Phase 2 — NEXT (see Status): keyboard MVP. Writing strip, candidate bar (3–5), space, backspace,
  return, globe key (`advanceToNextInputMode`). Insert via `textDocumentProxy`.
  Commit top candidate after a pause or on tap. Auto spaces. iPad height,
  light/dark. Host app setup screen + model status. Measure memory on device.
- Phase 3: pre-context (last ~20 chars of `documentContextBeforeInput`) + writing
  area size to ML Kit. Scribble-to-delete gesture. Punctuation, numbers, haptics.
- Phase 4 (optional, ask first): Claude API "clean up". Needs Full Access + API
  key in Keychain. Report cost and latency before building.

Plan B: if the keyboard can't fit in memory, keep the standalone app (write,
copy, paste) and propose a Share/Action extension or a Shortcut.

## Findings so far (Phases 0–1, 2026-11-05)
- Signing: certificate "Apple Development: <apple-id email> (…)" with O = the user's own
  name, OU = Personal Team ID → that is how to tell the Personal Team from the employer
  team. Team ID is only in Local.xcconfig.
- App Groups DO work on the free Personal Team: the Xcode-managed profiles for both
  targets carry `group.com.tany4.greekink`. Profiles expire after 7 days.
- `$(BUNDLE_ID_PREFIX)` in .entitlements is expanded by Xcode at signing time (verified
  with `codesign -d --entitlements`).
- Xcode 27 no longer caches the team list in its preferences; to get a Team ID, pick the
  team once in Signing & Capabilities and read DEVELOPMENT_TEAM from the pbxproj.
- XcodeGen 2.46 writes pbxproj objectVersion 77; CocoaPods 1.15 only reads ≤ 63, so
  `project.yml` has a postGenCommand that rewrites it to 60. Also `fileGroups` must list
  Local.xcconfig or CocoaPods complains about an orphan file reference.
- ENABLE_USER_SCRIPT_SANDBOXING must be NO (CocoaPods copy scripts write into Pods/).
- ML Kit links into the keyboard extension with APPLICATION_EXTENSION_API_ONLY = YES,
  no build errors. Debug keyboard binary is ~33MB on disk (ML Kit is static); 7 small
  dynamic frameworks are embedded in the app and shared with the extension.
- iPad: UDID <IPAD-UDID>, "iPad". Developer Mode enabled.
  First launch needs Settings > General > VPN & Device Management > trust.
- Keyboard memory on the iPad Air M1 / iPadOS 27 (Phase 0 keyboard, ML Kit linked but not
  loaded): 8.3 MB used, 81.7 MB headroom → the kill limit is ~90 MB on this device, not
  the 48–60 MB assumed. ML Kit model (~20 MB) should fit; re-measure once it is loaded.
- Without Full Access the keyboard can READ the App Group container but NOT write to it
  ("no permission" on write). So: host app downloads the model, keyboard reads it.
  Phase 2 must test whether ML Kit can load a model from a read-only shared path.
- ML Kit 8.0.0 bug: `DigitalInkRecognitionContext(preContext: nil, …)` crashes the recognizer
  thread (strlen on NULL). Always pass `preContext ?? ""`. Crash logs come off the iPad with
  `xcrun devicectl device copy from --domain-type systemCrashLogs --source . --destination <dir>`.
- ML Kit model storage (seen on the iPad): the app's own
  `Library/Application Support/com.google.mlkit.vision.digitalinkrecognition/`.
  `UnzippedModelCache/` holds the Greek model as 3 files, ~23 MB (`el.*.compact.fst` 21.5 MB,
  `indy_lstm.greek.*.tflite` 1.8 MB, a small recospec). `Download/` keeps MDD download state
  (zipped FileData ~12 MB, FileGroupMetadata, `MDDCore_Lock_File.internal`, so MDD may want
  write access). The keyboard has its own container, so Phase 2 must test pointing ML Kit at a
  shared copy (e.g. symlink from the keyboard's Application Support into the App Group) before
  falling back to Full Access.
- Files can be pulled off the app without copy-paste:
  `xcrun devicectl device copy from --device <udid> --domain-type appDataContainer
  --domain-identifier com.tany4.greekink --source Documents/misreads.json --destination <file>`.
  Copying the whole `Library` aborts on SplashBoard snapshots; copy sub-folders. The prototype
  app also writes `Documents/diagnostics.log` (touch events, recognition timing, misreads).
- Pencil in the full-screen app: with `isMultipleTouchEnabled = false` the resting palm took the
  only touch slot and Pencil touches were never delivered (the Phase 0 keyboard sat at the
  bottom edge, so no palm). The canvas now keeps multi-touch on, lets a Pencil touch replace a
  finger/palm stroke, ignores finger touches for 1.5 s after Pencil contact, and discards
  cancelled touches instead of committing them.
  Confirmed on the iPad: 101 Pencil strokes in a row, all delivered and committed.
- A palm that rests on the glass BEFORE the Pencil arrives is a normal finger touch to iPadOS
  (system palm rejection only kicks in once the Pencil is on or near the screen). Measured
  `majorRadius` on the iPad Air: palm 52–62 pt, Pencil 0; a fingertip is ~20–25 pt. The canvas
  ignores direct touches wider than 40 pt (`palmRadius`), at touch-down and mid-stroke.
- Phase 1 result: on the iPad Air M1 recognition takes ~50 ms for 3 strokes and ~140 ms for a
  93-stroke / 7380-point sentence (ML Kit call only). Long Greek sentences come out right,
  including tonos, dialytika with tonos (Μαΐου) and capitals. Final sigma not tested yet.
- Latin words inside Greek text come out as Greek letters ("Apple" → "Αρρα δω"): the `el`
  model only emits Greek script and ML Kit has no mixed Greek/Latin model. Options for Phase 3:
  a Latin toggle key, or also run the `en` model and show its top candidate as an extra chip
  (second recognition ~100 ms, second model in RAM; measure in the keyboard first).
- Misreads so far (el): finger, 19 strokes: "Καλημέρα αγάπη μου!" → "Καλημέρου αγάπη μου!"
  (final α → ου). Pencil, 17 strokes: "Καλημέρα αγάπη μου Μαΐου" → "Καλημέρα γάπη του Μαΐου"
  (leading α of αγάπη dropped, μ → τ/κ). Accents, dialytika and capitals right both times.
  One candidate contained a Latin "g" ("gάπη"), so the el model can emit some Latin letters,
  but its language model strongly prefers Greek words.
- GitHub pushes sometimes fail with `remote: fatal error in commit_refs_rules`
  (GitHub-side, intermittent). Just retry.

## Commands
- Regenerate project: `tools/xcodegen/bin/xcodegen generate && pod install`
- Open: `open GreekInk.xcworkspace`
- Build + install + launch on the iPad: `scripts/install-ipad.sh` (see README).
- Unsigned compile check: `xcodebuild -workspace GreekInk.xcworkspace -scheme GreekInk -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`
