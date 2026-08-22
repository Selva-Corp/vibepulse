# Shipping AgentTap to the App Store

Everything technical is prepared; these are the steps only the account
holder can do, in order.

## One-time

1. **Enroll** in the Apple Developer Program ($99/yr): developer.apple.com
   → Account → Enroll. (Personal enrollment is fine.)
2. In Xcode → Settings → Accounts, sign in; the project's Automatic signing
   will pick up your team.
3. **Host the privacy policy**: `PRIVACY.md` needs a public URL — pushing
   this repository to GitHub makes the file's page a valid URL.
4. In **App Store Connect** → My Apps → "+" → New App:
   - Platform watchOS, Name **AgentTap**, bundle id `com.jgselva.agenttap`
     (create it when prompted), SKU e.g. `agenttap-1`.

## Every release

Watch-only apps ship inside a stub iOS container (`AgentTapContainer`,
bundle `com.jgselva.agenttap`; the watch app itself is
`com.jgselva.agenttap.watchkitapp`). This is deliberate: Xcode 26's
Organizer/exportArchive never offer App Store distribution for a bare
watchOS archive (Apple forums thread 817223, acknowledged as a likely bug);
the container makes the archive iOS-typed, which restores the option. The
App Store Connect app record is therefore an **iOS-platform** record on the
container's bundle ID — customers still see it as an Apple Watch app.

From `watch/` — the keyless build is what ships (users pair at runtime):

```sh
xcodegen generate
xcodebuild archive -project AgentTap.xcodeproj -scheme AgentTapStore \
  AGENTTAP_NO_KEY=1 \
  -destination 'generic/platform=iOS' \
  -archivePath build/AgentTap.xcarchive
open build/AgentTap.xcarchive   # Organizer: Distribute App -> App Store Connect -> Upload
```

(Headless `-exportArchive` upload additionally needs an App Store Connect
API key; the Organizer path uses Xcode's signed-in account.)

Then in App Store Connect:
- attach the uploaded build to the version,
- upload `appstore/screenshots/*.png`,
- paste `LISTING.md` fields and `REVIEW-NOTES.md` into Notes,
- fill the privacy questionnaire: **Data Not Collected** (all of it),
- submit. TestFlight first is one extra click and worth it.

Expect the review to test demo mode (the notes walk them through it). If
the name AgentTap is taken in your storefront, any name works — the
in-repo rename is scripted and takes minutes.
