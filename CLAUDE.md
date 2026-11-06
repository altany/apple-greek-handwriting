# GreekInk — Greek handwriting keyboard for iPad

Personal iPad keyboard: handwrite Greek with Apple Pencil, get text in any app.
Apple's Scribble has no Greek and no API to add one, so this is a custom keyboard.
Personal use only. No App Store.

## Status (2026-11-06) — read this first
- Phase 0, 1 and 2 are DONE. Phase 3 is IN PROGRESS (user said "go" on 2026-11-06). Built and
  installed, waiting for the user's test round:
  - Pre-context: the keyboard passes the last 20 chars before the cursor + the auto space it is
    about to add (so ML Kit treats the ink as a new word), and trims/dedupes candidates. Per the
    docs ML Kit emits a leading space when it infers a word break from pre-context. Check the
    keyboard log ("pre-context …, candidates: "…"") for misreads and leading spaces.
  - Scribble to delete: ML Kit iOS 8.0.0 has NO gesture classifier. `el-x-gesture` fails as
    "unknown model tag" on the iPad, and the SDK binary's built-in model list has only the text
    languages plus zxx-Zsye-x-emoji, zxx-Zsym-x-autodraw, zxx-Zsym-x-shapes (checked with
    `strings`). So `GreekInkKeyboard/ScribbleDetector.swift` detects a zigzag itself (one stroke,
    ≥5 horizontal reversals, ≥50 pt wide, height ≤ 0.9 × width). With other ink on the strip it
    erases the ink; on an empty strip it deletes the last word (+ the space before it). Every
    stroke's verdict is logged ("stroke: … reversals …") to tune thresholds. Not yet tested.
  - Test round 2026-11-06 13:33–13:38 (keyboard, Pencil): 5 candidates now show. All of these came
    out right: "Νερό στη βάρκα μας" (the ν→μ misread is gone), "Παράπονο", "μέμφομαι", "ωραίο"
    (written after "μέμφομαι ", no leading space returned), en "Nature", "Hurt". Near misses:
    "Natur boy" (top) for "Nature boy", "μιας" top over "μας" once, "1η" vs "ξη" in a date.
    Scribble detector: no false positives. Ordinary letters reach at most 6 reversals but are
    tall (50×57), or have ≤4. No scribble was seen in the log, so it is still untested.
    Memory 9–15 MB over many keyboard reloads. The user writes on new lines, so pre-context is
    often just "\n".
  - Punctuation and numbers: no code yet; the user tests handwriting them first.
  - Haptics: dropped. The iPad Air has no Taptic Engine.
- Phase 2 results (first keyboard test, 2026-11-05 21:29, no Full Access):
  - Model sharing works: app copies ML Kit's folder into the App Group, keyboard copies it into
    its own container (13 ms, APFS clone) and adds metadata files renamed to its bundle id.
    `isModelDownloaded` = true for el and en, warm-up recognition OK. Full Access not needed.
  - Memory with the el model loaded: 9.2 MB used, 80.8 MB headroom. The model is memory-mapped,
    so it barely counts. Plan B is not needed.
  - Timing in the keyboard: warm-up 53 ms, 12 strokes / 1193 points recognised in 93 ms.
  - Bug found and fixed: only 1 candidate showed (warm-up cached a maxResults-1 recognizer).
    Reinstalled; the 5-candidate bar is not yet re-tested by the user.
- Fixing a misread word mid-text: the user has a way with the current keyboard; no work wanted.
- Repo is PUBLIC since 2026-11-06 (user chose: rewrite history keeping commits, MIT, make public).
  History was rewritten with git filter-branch: Team ID, iPad UDID and the user's first name
  scrubbed from every commit, author/committer email set to the GitHub no-reply address, then
  force-pushed. Local `git config user.email` is the no-reply address; keep it that way. Never
  commit the Team ID, UDID, real name or personal email. Orphaned pre-rewrite commits may stay
  reachable on GitHub by hash until GitHub garbage-collects them (only Support can purge).
- Docs for the user: `docs/blog-brief.md` (facts for their blog-writing agent),
  `docs/app-store-investigation.md` (competitors, Guideline 4.4.1, what a store release needs).
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
  `Recognition/ModelStorageInspector.swift`, `AppGroup.swift` (container URL),
  `MemoryFootprint.swift`.
- `GreekInk/` (host app, SwiftUI): `ContentView.swift` (Write/Setup tabs, owns the objects),
  `Prototype/` (PrototypeView + PrototypeViewModel, `InkCanvas` wrapper, `MisreadLog` →
  Documents/misreads.json),
  `Setup/SetupView.swift`.
- `GreekInkKeyboard/KeyboardViewController.swift`: the Phase 2 keyboard (writing strip,
  candidate bar, globe, ΕΛ/EN, space, backspace, return). Pause 800 ms → recognise → insert top
  candidate with auto space; tapping an alternative replaces the inserted word.
- `Shared/Recognition/ModelSharing.swift` (app → App Group → keyboard model copy),
  `Shared/Diagnostics/DiagnosticsLog.swift` (each process writes its own Documents/diagnostics.log),
  `GreekInk/Setup/KeyboardModelExporter.swift` (auto copy when downloaded models change).
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
  `el` (Greek) and `en`. No gesture model on iOS (see Status); scribbles are detected in code. Input is strokes
  (x, y, t), not images. Model ~20MB, downloaded on first use.
- Optional later (Phase 4, ask first): "clean up" button via the Claude API.
- Bundle IDs: `com.tany4.greekink` (app), `com.tany4.greekink.keyboard`
  (keyboard). App Group: `group.com.tany4.greekink`.
- Signing: free "Personal Team" ONLY. The Apple ID also belongs to other teams;
  never use them. Team ID lives in git-ignored `Local.xcconfig`
  (see `Local.xcconfig.example`), nowhere else.
- GitHub: PUBLIC repo `apple-greek-handwriting` on the personal account `altany` (MIT).
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
1. Memory [MEASURED: 9.2 MB with the el model loaded in the keyboard, 80.8 MB headroom]: limit ~90MB on the iPad
   Air M1 (see Findings), not 48–60MB. ML Kit model alone ~20MB in RAM. Measure on the real
   iPad as soon as the keyboard loads the model.
2. Network: without "Allow Full Access" a keyboard extension has no network and
   cannot download the model. Plan (a): host app downloads, shares via App Group.
   Plan (b): extension downloads with Full Access on. App Groups may not work on
   a free Personal Team. A keyboard without Full Access may only read (not
   write) the App Group container. ML Kit picks its own model folder. Test all.
   [App Groups on the Personal Team: VERIFIED. Keyboard read-only in the group: VERIFIED.
   ML Kit loading the model copied from the App Group: VERIFIED, no Full Access.]
3. ML Kit may not be extension-safe (APPLICATION_EXTENSION_API_ONLY). [Links and builds:
   VERIFIED. Recognition running inside the extension: VERIFIED.]
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
- Phase 2 — DONE: keyboard MVP. Writing strip, candidate bar (3–5), space, backspace,
  return, globe key (`advanceToNextInputMode`). Insert via `textDocumentProxy`.
  Commit top candidate after a pause or on tap. Auto spaces. iPad height,
  light/dark. Host app setup screen + model status. Measure memory on device.
- Phase 3 — NEXT, ask first: pre-context (last ~20 chars of `documentContextBeforeInput`) + writing
  area size to ML Kit. Scribble-to-delete gesture. Punctuation, numbers, haptics. Candidate:
  extra `en` chip (measure first).
- Phase 4 (optional, ask first): Claude API "clean up". Needs Full Access + API
  key in Keychain. Report cost and latency before building.

Plan B: if the keyboard can't fit in memory, keep the standalone app (write,
copy, paste) and propose a Share/Action extension or a Shortcut.

## Findings so far (Phases 0–1, 2026-11-05)
- Signing: certificate "Apple Development: <apple-id email> (…)" with O = the user's own
  name, OU = Personal Team ID → that is how to tell the Personal Team from the others.
  Team ID is only in Local.xcconfig.
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
- iPad: UDID and Team ID are in the local auto-memory, not in git (`xcrun devicectl list
  devices` shows the UDID). Developer Mode enabled.
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
- Latin in the el model, later test in the app (2026-11-05 21:18): el read "Apple" correctly and
  "Hello, αγάπη μου!" with both scripts; en read "Good morning". So the earlier "Αρρα δω" is not
  the rule. The user reports English works; it was tested in the app, not yet in the keyboard.
- First keyboard misread (Pencil, 12 strokes): "νερό στη βάρκα μας" → "μερό στη βάρκα μας"
  (ν → μ at the start). Only 1 candidate was shown then (bug, fixed).
- ML Kit's MDD metadata files are named `<bundle id>.com.google.mlkit.mdd.cellular.<model
  name>.<lang>.<number>` (e.g. `com.tany4.greekink.com.google…el.0001793897628892587`), protobuf
  inside, no absolute paths (only file hashes + dl.google.com URLs). Folder also has
  `Download/FileData/<sha1>` (the zips), `FileGroupIsolation/`, `LatestCompletedLookup/`,
  `scratch/` (download sessions, not copied). App preferences hold nothing ML Kit needs.
- The keyboard's own container is readable from the Mac: `--domain-type appDataContainer
  --domain-identifier com.tany4.greekink.keyboard --source Documents/diagnostics.log`.
  `--domain-type appGroupDataContainer` only lists the group's Library folder, not files the
  app wrote at the group root, so check the App Group copy through the app log instead.
- In the Claude desktop app's shell `pod install` crashes (Unicode normalization, ASCII-8BIT)
  because LANG is unset. Run it with `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`.
- GitHub pushes sometimes fail with `remote: fatal error in commit_refs_rules`
  (GitHub-side, intermittent). Just retry.

## Commands
- Regenerate project: `tools/xcodegen/bin/xcodegen generate && pod install`
- Open: `open GreekInk.xcworkspace`
- Build + install + launch on the iPad: `scripts/install-ipad.sh` (see README).
- Unsigned compile check: `xcodebuild -workspace GreekInk.xcworkspace -scheme GreekInk -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`
