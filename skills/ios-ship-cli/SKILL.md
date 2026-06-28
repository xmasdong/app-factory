---
name: ios-ship-cli
description: Use when shipping an iOS app to TestFlight or App Store from the command line without Xcode UI, configuring fastlane for the first time on a project, debugging upload errors ("Cloud signing permission error", "No Accounts", "Provisioning profile doesn't include signing certificate", "bundle version already used"), bumping build numbers, or porting an established release pipeline to a fresh Flutter / native iOS project. Triggers on testflight upload, fastlane beta, altool, xcodebuild exportarchive, cloud signing error, provisioning profile mismatch, app-specific password, ASC API key, ipa export, app store upload.
---

# iOS Ship CLI — TestFlight + App Store from the terminal

Tactical playbook for getting any iOS app (Flutter or native) signed,
exported, and uploaded to TestFlight from the command line on macOS,
without ever opening Xcode Organizer.

The pipeline is built around the **App Store Connect API key**, not
Apple ID + password. Once configured per-developer-account, the same
key works for every app under that team on every Mac that has the key.

## When to use this skill

- First time shipping an iOS app to TestFlight from a new project
- Apple ID + GUI Xcode upload is flaky / not an option (CI/CD, headless)
- Hit "Cloud signing permission error" on `xcodebuild -exportArchive`
- Hit "No Accounts" or "No signing certificate iOS Distribution found"
- Need to bump build number reliably without remembering the format
- Bringing up a fresh Flutter or native iOS app and want the same
  release flow as the previous one

## Mental model

The release pipeline has **three credential layers**, and most
breakage is one of these layers being out of sync:

1. **ASC API key** (account-wide, reusable across all apps)
   - `Issuer ID` + `Key ID` + `AuthKey_XXX.p8`
   - Created once per developer account
   - Replaces all Apple ID + 2FA + app-specific-password flows
2. **Apple Distribution certificate** (account-wide, reusable across all apps)
   - In the local Mac keychain
   - One per developer account, valid 1 year, auto-renewed by Xcode
3. **App Store provisioning profile** (per-app, **not reusable**)
   - Lives on Apple's developer portal + cached at
     `~/Library/MobileDevice/Provisioning Profiles/`
   - Bundle ID + Distribution cert + capabilities (Push / IAP / etc.)
   - Auto-created by `fastlane sigh` per app, no GUI clicks needed

The fourth concept — **fastlane** — is just an automation wrapper that
calls the same `xcodebuild` / `altool` / Apple API endpoints you'd
call by hand, plus retries the flaky ones.

## Where everything lives on disk

Memorize these — half of all "it broke" moments are a file in the
wrong place.

| Artifact | Canonical path | Created by | Scope |
|---|---|---|---|
| ASC API `.p8` key | `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` | Manually downloaded from ASC (one-time, only-once download) | Per developer account |
| fastlane API key bundle | `~/.appstoreconnect/api_key.json` | Hand-crafted heredoc wrapping the `.p8` + IDs | Per developer account |
| Apple Distribution cert (private key + public cert) | macOS **login keychain** (`~/Library/Keychains/login.keychain-db`) | Xcode → Settings → Accounts → Manage Certificates, or `fastlane match`/`cert` | Per developer account, per Mac |
| Apple Development cert (device install) | Same login keychain | Xcode auto-creates first time you build for device | Per developer + per Mac |
| Provisioning profile (installed) | `~/Library/MobileDevice/Provisioning Profiles/<UUID>.mobileprovision` | `fastlane sigh` (auto-installs after download) | Per app, refreshed on cert change |
| Provisioning profile (fastlane source copy) | `<project>/ios/fastlane/profiles/AppStore_<bundle-id>.mobileprovision` | `fastlane sigh` (also writes here for the lane to reference) | Per project — gitignored |
| ExportOptions.plist | `<project>/ios/fastlane/ExportOptions.plist` | Hand-written; committed | Per project |
| Fastfile | `<project>/ios/fastlane/Fastfile` | Hand-written; committed | Per project |
| Xcode account session | `~/Library/Developer/Xcode/UserData/IDETemplateMacros.plist` + login.keychain (token-style) | Xcode → Settings → Accounts → +Apple ID | Per Mac (NOT used by CLI flow with API key) |
| .xcarchive (build output) | `<project>/build/ios/archive/Runner.xcarchive` | `flutter build ipa` / `xcodebuild archive` | Per build — gitignored |
| Final signed IPA | `<project>/build/ios/ipa/<AppName>.ipa` | `xcodebuild -exportArchive` | Per build — gitignored |

Quick verification commands:

```bash
# Is the .p8 in place?
ls ~/.appstoreconnect/private_keys/

# Is the fastlane key bundle valid JSON?
jq . ~/.appstoreconnect/api_key.json

# Which signing identities are in the keychain?
security find-identity -p codesigning -v

# Which provisioning profiles are installed?
ls ~/Library/MobileDevice/Provisioning\ Profiles/

# What's inside a specific provisioning profile?
security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/<UUID>.mobileprovision \
  > /tmp/p.plist && /usr/libexec/PlistBuddy -c "Print :Name" /tmp/p.plist
```

## One-time setup per Mac

Do this once per developer machine. After this, every new app is just
3 steps (per-app setup below).

### 1. Create an ASC API key (10 min, once per account)

[appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api)

- Top tab: **Team Keys**
- Click **+** → Name `ci`, Access role **App Manager** → Generate
- Note the **Issuer ID** (page header, UUID) and **Key ID** (10-char)
- Download `AuthKey_<KEY_ID>.p8` — **only downloadable once**, store safely

Move the .p8 to the canonical path:

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
```

Create `~/.appstoreconnect/api_key.json` (fastlane reads this):

```bash
P8=$(cat ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 | awk '{printf "%s\\n", $0}')
cat > ~/.appstoreconnect/api_key.json <<EOF
{
  "key_id": "<KEY_ID>",
  "issuer_id": "<ISSUER_ID>",
  "key": "${P8%\\n}",
  "duration": 1200,
  "in_house": false
}
EOF
```

### 2. Install fastlane

```bash
brew install fastlane
```

Verify:

```bash
fastlane --version
```

### 3. Create Apple Distribution cert (one-time, 30 sec)

The first time you run any fastlane lane that needs to sign, it will
prompt to create the Distribution cert. If you prefer to seed it
manually first:

- Xcode → Settings → Accounts → click team → **Manage Certificates...**
- Bottom-left **+** → **Apple Distribution** → Done

Verify it's in keychain:

```bash
security find-identity -p codesigning -v
# Expect: "Apple Distribution: <Your Name> (<TEAMID>)"
```

## Per-app setup (every new app, ~2 minutes)

### 1. Add the app on App Store Connect

Only once per app:

- ASC → My Apps → **+** → New App
- Pick the bundle ID (must match `CFBundleIdentifier` in Info.plist)
- Fill name + primary language + SKU

### 2. Drop the fastlane templates into `ios/`

From the project root:

```bash
mkdir -p ios/fastlane
```

Copy **`Fastfile`**, **`ExportOptions.plist`** (see Templates below)
into `ios/fastlane/`.

Edit three places:

- `Fastfile` → `APP_IDENTIFIER` constant
- `Fastfile` → IPA filename (`PawSnap.ipa` etc.)
- `ExportOptions.plist` → `provisioningProfiles` dict key (bundle ID)
   and value (profile name — convention is `<bundle-id> AppStore`)

### 3. Add fastlane noise to .gitignore

Append to `ios/.gitignore`:

```
fastlane/profiles/
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots
fastlane/test_output
```

### 4. First release (creates profile too)

```bash
cd ios && fastlane beta
```

The first time, `sync_profile` (called inside `beta`) creates the
App Store provisioning profile via Apple's API. Subsequent runs reuse
it.

## Per-release (every time you ship)

```bash
cd ios && fastlane beta
```

That's it. The lane:

1. Bumps pubspec / Info.plist build number (`+N → +N+1`)
2. Refreshes the provisioning profile from Apple
3. Runs `flutter build ipa` (Flutter projects) — its export step
   often fails with "Cloud signing permission error" on individual
   dev accounts, **this is expected**
4. Re-exports the archive with manual signing pointed at the
   sigh-downloaded profile — produces a clean IPA
5. Uploads to TestFlight via `pilot` + ASC API key

Processing in ASC takes 5-30 min, then the build appears in
TestFlight → Internal Testing → add to a group → tester apps refresh.

## Templates

### `ios/fastlane/Fastfile`

```ruby
default_platform(:ios)

# All auth flows through the shared ASC API key at
# ~/.appstoreconnect/api_key.json. Portable to any Mac that has the
# key — no Apple ID prompts, no GUI clicks.
#
# All paths are computed from PROJECT_ROOT (two dirs up from this
# Fastfile) so they don't depend on what cwd fastlane's `sh` action
# happens to inherit. The naive `cd ../..` form silently produces
# WRONG paths because fastlane runs from `ios/fastlane/`, not `ios/`.

API_KEY_PATH = File.expand_path("~/.appstoreconnect/api_key.json")
PROJECT_ROOT = File.expand_path("../..", __dir__)
ARCHIVE_PATH = "#{PROJECT_ROOT}/build/ios/archive/Runner.xcarchive"
IPA_DIR      = "#{PROJECT_ROOT}/build/ios/ipa"
EXPORT_OPTS  = "#{__dir__}/ExportOptions.plist"
PUBSPEC      = "#{PROJECT_ROOT}/pubspec.yaml"
APP_IDENTIFIER = "com.example.YOURAPP"     # CHANGE PER APP
IPA_FILENAME   = "YOURAPP.ipa"             # CHANGE PER APP (matches scheme name)
IPA_PATH       = "#{IPA_DIR}/#{IPA_FILENAME}"

platform :ios do
  desc "Bump the iOS build number in pubspec.yaml (Flutter projects)"
  lane :bump do
    sh "perl -i -pe 's/^(version:\\s*\\d+\\.\\d+\\.\\d+\\+)(\\d+)$/$1.($2+1)/e' #{PUBSPEC}"
    sh "grep '^version:' #{PUBSPEC}"
  end

  desc "Refresh / create the App Store provisioning profile"
  lane :sync_profile do
    sigh(
      app_identifier: APP_IDENTIFIER,
      api_key_path: API_KEY_PATH,
      force: true,
      output_path: "fastlane/profiles",
    )
  end

  desc "Build + upload to TestFlight"
  lane :beta do
    bump
    sync_profile
    # Two-stage build:
    # 1. `flutter build ipa` produces the .xcarchive cleanly. Its
    #    bundled IPA-export step uses Apple's cloud signing which
    #    individual-dev accounts hit "Cloud signing permission error"
    #    on — we tolerate that step failing.
    # 2. xcodebuild -exportArchive re-exports the archive with manual
    #    signing pointing at the sigh-downloaded profile, producing
    #    a clean App Store IPA every time.
    Dir.chdir(PROJECT_ROOT) do
      sh "flutter build ipa --release --export-method app-store || true"
    end
    sh "rm -f #{IPA_DIR}/*.ipa"
    sh "xcodebuild -exportArchive " \
       "-archivePath #{ARCHIVE_PATH} " \
       "-exportPath #{IPA_DIR} " \
       "-exportOptionsPlist #{EXPORT_OPTS}"

    pilot(
      ipa: IPA_PATH,
      api_key_path: API_KEY_PATH,
      skip_waiting_for_build_processing: true,
      skip_submission: true,
    )
  end
end
```

### `ios/fastlane/ExportOptions.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
    <key>signingCertificate</key>
    <string>Apple Distribution</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.example.YOURAPP</key>
        <string>com.example.YOURAPP AppStore</string>
    </dict>
</dict>
</plist>
```

## Native iOS (no Flutter) adjustments

For pure-native iOS, replace the `beta` lane build step:

```ruby
# Replace the two `sh` lines with build_app
build_app(
  scheme: "YourScheme",
  export_method: "app-store",
  export_options: {
    method: "app-store-connect",
    signingStyle: "manual",
    teamID: "YOUR_TEAM_ID",
    provisioningProfiles: {
      APP_IDENTIFIER => "#{APP_IDENTIFIER} AppStore",
    },
  },
)
```

The rest (sync_profile, pilot, API key) is identical.

## Troubleshooting

| Error message | Root cause | Fix |
|---|---|---|
| `No Accounts` / `No signing certificate "iOS Distribution" found` | Distribution cert missing from keychain | `security find-identity -p codesigning -v` → if empty, Xcode → Settings → Accounts → Manage Certificates → + Apple Distribution |
| `Provisioning profile doesn't include signing certificate "Apple Distribution"` | Profile on Apple servers references an old / different Dist cert than the one in keychain | `fastlane sync_profile` (forces fresh download with current cert) |
| `Cloud signing permission error` | Apple cloud-signing service rejects the API key for automatic profile renewal on individual-dev accounts | Use `signingStyle: manual` + explicit profile (see ExportOptions.plist template) |
| `The bundle version must be higher than the previously uploaded version: 'N'` | You re-uploaded an IPA that wasn't bumped, or the IPA on disk is a stale earlier build | Run `fastlane bump` first; delete `build/ios/ipa/*.ipa` before re-export |
| `Failed to Use Accounts` (xcodebuild from CLI) | Xcode-GUI account session not visible to CLI | Use ASC API key path (`-authenticationKeyPath` + `-authenticationKeyID` + `-authenticationKeyIssuerID`) instead of relying on the Xcode account |
| `Codesigning identity ... not found` | Cert in non-login keychain | `security default-keychain -s ~/Library/Keychains/login.keychain-db` |
| altool exit code 31 with `-19232` | Apple uniqueness check — version+build pair already exists in ASC | Bump build number (`+N+1` in pubspec.yaml or Info.plist) |
| `No profiles for 'com.x.y' were found` during xcodebuild | Profile not in `~/Library/MobileDevice/Provisioning Profiles/` | `fastlane sync_profile` re-runs and installs there |
| `App Store Connect API key ... is not valid` | api_key.json malformed (literal `\n` not preserved properly) | Re-run the heredoc that builds api_key.json; verify with `jq . ~/.appstoreconnect/api_key.json` |

## Common quick checks

```bash
# Verify ASC API key is readable + valid
xcrun altool --list-providers --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>

# Verify code signing identities present
security find-identity -p codesigning -v

# Verify the installed provisioning profile UUID + name
security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision \
  > /tmp/p.plist && /usr/libexec/PlistBuddy -c "Print :Name" /tmp/p.plist

# Verify the archive's build number before export
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" \
  build/ios/archive/Runner.xcarchive/Info.plist
```

## Internal test invite (after upload lands)

After `fastlane beta` succeeds, ASC takes 5-30 min to process. Then:

- ASC → app → TestFlight tab → wait for **Ready to Submit**
- If "Missing Compliance" — click → Export Compliance → encryption
  uses only exempt algorithms → No
- Left sidebar → Internal Testing → click your group → Testers tab →
  **+** → add your tester → ASC sends invite email
- Tester opens email → "View in TestFlight" → app installs

Internal testers must be added as Users in ASC first (Users and
Access tab), with at least Developer or App Manager role. Apple
allows up to 100 internal testers per app, no Apple review.

External testers (up to 10,000) require a Beta App Review (~24h
first time, faster on subsequent builds for the same version).

## Cross-references

- Once the build is in TestFlight and you're filling out App Review
  prep, the **app-store-review-survival** skill covers the human-review
  side (metadata, App Privacy questionnaire, screenshot rules,
  rejection patterns).
- For releasing screenshots, see **app-store-screenshots** skill.
