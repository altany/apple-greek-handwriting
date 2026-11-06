# Could GreekInk be a real App Store app?

Investigation, 6 Nov 2026. Short answer: yes, and the gap is real. Apple does not offer Greek
handwriting, and the only store app that claims it is a general 100+ language keyboard with
ads and tracking. The technical core already meets Apple's keyboard rules. The work left is
mostly product polish, an iPhone layout, privacy paperwork and a paid developer account.

## Does something like this exist?

| Option | Greek handwriting? | Notes |
|---|---|---|
| Apple Scribble (iPadOS 27) | No | 44 language variants, Greek not among them ([Apple feature availability](https://www.apple.com/ios/feature-availability/)) |
| Apple handwriting keyboards | No | Only Chinese (Simplified, Traditional), Cantonese, Japanese (same page) |
| [Handwriting Keyboard](https://apps.apple.com/us/app/handwriting-keyboard/id1360599939) (Reeba Sebastian) | Claims yes, among "100+ languages" | Free + in-app purchases $2.99 / $12.99 / $19.99 / $49.99. Ads. Privacy label: data used to track you (identifiers, usage, diagnostics) for third-party advertising. iPhone + iPad, iOS 17+, 4.5★ from ~1K ratings, updated 4 Nov 2026. Says "100% offline, on-device". Engine not named; 100+ offline languages fits ML Kit. Reviews: no predictions, small writing area, missing customisation. Nothing Greek-specific (tonos, final ς, Greek punctuation) is mentioned. |
| "Greek Handwriting Keyboard" (id1611562781) | Name says so | Turned up in a search of the UK store; the US store page returns 404 and the UK page could not be read. Status unknown: possibly removed or regional. Worth a look in the Greek store from the iPad. |
| MyScript Stylus | Was a handwriting keyboard | Retired by MyScript ([retired apps](https://www.myscript.com/retired-apps)) |
| Greek learning apps (e.g. Write It! Greek) | Recognition inside the app only | Not keyboards |

Positioning that is still open: a **Greek-first, Pencil-first, private** handwriting keyboard.
No ads, no tracking, works without Full Access, tuned for τόνος, dialytika, final ς and Greek
punctuation (; and ·), palm-friendly canvas, mixed Greek/Latin via the ΕΛ/EN key.
Possible extra audiences: Greek learners, the diaspora (writes Greek, types it badly), people
who prefer handwriting, Ancient/polytonic Greek users (would need checking: ML Kit's `el` model
is modern Greek).

## Apple's rules for keyboards (Guideline 4.4.1)

Text as read from the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
(from an extraction of the page, worth re-reading verbatim before submitting). Keyboards must:

- provide keyboard input functionality: **yes**;
- provide a method for progressing to the next keyboard: **yes** (globe key);
- remain functional without full network access and without requiring Full Access: **yes**,
  this is exactly what the App Group model copy solved;
- collect user activity only to improve the keyboard on the device: **yes**, the keyboard has
  no network, so nothing it sees leaves the iPad.

They must not launch other apps besides Settings, or repurpose keys (e.g. hold return to open
the camera). GreekInk does neither.

## What is missing for a store release

**Account and signing (needs your decision, touches the Apple account)**
- Apple Developer Program, US$99/year (individual). The free Personal Team can't publish, and
  apps signed with it expire after 7 days.
- New bundle IDs and App Group under the paid team. The name "GreekInk" needs a check for
  conflicts on the store.

**Product**
- iPhone support. The project is iPad-only today; the writing strip would be smaller but the
  competitor shows it works. Doubles the audience.
- Numbers and punctuation: handwriting them may be enough (to test in Phase 3), otherwise a
  small key row. Reviewers will type into all sorts of fields.
- Onboarding in the app: enable the keyboard, download the model, try it. Today the Setup tab
  does this in a developer-ish way. The first model download (~12 MB) needs a network.
- Greek and English app UI (localisation).
- Remove the developer bits: diagnostics logs, the memory number in the status line, the test
  canvas or turn it into a "practice" screen.
- Settings worth having: pause length, stroke width, left-handed layout, keyboard height.
- Accessibility labels on the keys, Dynamic Type in the app.

**Privacy and legal**
- A privacy policy URL (required for every app).
- The App Store privacy label. GreekInk's own code collects nothing. ML Kit itself may send
  usage and performance data to Google from the app (the app's caches show Google logging
  folders), so check Google's ML Kit data-disclosure guidance and declare what applies.
  The keyboard has no network, so nothing is sent from it.
- A privacy manifest (`PrivacyInfo.xcprivacy`) for the app and the keyboard, listing the
  "required reason" APIs the code uses (UserDefaults, file timestamps). Check that the ML Kit
  pods ship their own manifests.
- ML Kit's terms allow free use in commercial apps; re-read the current terms before release.

**Engineering risks**
- CocoaPods' central repository goes read-only on 2 Dec 2026 and ML Kit has no Swift package.
  Existing versions keep installing, but future ML Kit updates may need a different route.
- If ML Kit ever changes how it names its model files, the keyboard copy could break. The
  keyboard already shows "model not available" and logs the folder, and a Full Access fallback
  download is possible (allowed, as long as the keyboard still works without it).

**Business**
- Price options: paid up front (e.g. €2.99–4.99), or free with a one-time unlock. The privacy
  angle ("no ads, no tracking, your handwriting never leaves your iPad") is the main differentiator against
  the competitor, so ads would undercut it.
- Size of the market is the real question: Greek speakers who handwrite on an iPad. Small, but
  underserved. A TestFlight beta with Greek friends and a Greek teacher or two would show
  whether people want it before polishing.

## Suggested path

1. Finish Phase 3 on the free account (it all carries over).
2. Ask 3–5 Greek-writing iPad users to try it (needs TestFlight, so a paid account, or their
   iPads on the Mac with the free account, max 3 apps and 7 days).
3. If the feedback is good: paid account, iPhone layout, onboarding, privacy work, submit.
