---
name: app-store-review-survival
description: Use when preparing an iOS app for first App Store submission, debugging an App Review rejection, or auditing App Store Connect (ASC) metadata before resubmit. Covers App Review Guideline 1.3 (Kids Category), 3.1.2 (subscriptions / EULA), 5.1.1-5.1.2 (privacy / consent / account deletion), permission prompts localization, sandbox IAP, build number bumping, screenshot rules, and the App Privacy questionnaire. Triggers on app store rejection, apple review, guideline 3.1.2, kids category, EULA, consent screen, IAP review, subscription disclosure, app review reply.
---

# App Store Review Survival Guide

Tactical playbook for getting an iOS app through App Review on the
**first** submission, plus rapid recovery when Apple rejects. Built
from real rejections, not Apple's documentation rephrased.

## When to use this skill

- Filling out App Store Connect metadata for the first time
- Got a rejection email from App Review — what does it actually mean?
- Submitting a build with in-app purchases or subscriptions
- Adding a privacy consent flow / account deletion path
- Drafting the reply in Resolution Center

## Mental model

App Review is **not** a feature audit. It's an enforcement pass on a
short list of high-cost guidelines:

1. **1.x — Safety**: kids, harassment, objectionable content
2. **2.x — Performance**: bugs, broken features, demo-only apps
3. **3.x — Business**: payments, IAP, third-party billing
4. **4.x — Design**: copy of another app, fake reviews
5. **5.x — Legal**: privacy, intellectual property, regulated content

Most rejections hit **1.3** (Kids), **2.1** (incomplete), **3.1.2**
(subscriptions), and **5.1.1** (privacy). Get those four right and
you'll usually pass.

## Pre-submission Checklist

Before clicking Submit, walk through every section below. Each is a
documented rejection trigger, not theoretical.

### A. Categories (avoid Kids trap)

- [ ] Primary Category set, NOT Kids Category unless the app is
      genuinely a kids-only product (no camera, no photo library
      access, no third-party links, no social, no IAP except parental
      gate)
- [ ] "Made for Kids" toggle OFF (ASC → App Information)
- [ ] **Photo apps cannot be in Kids Category — period**, even if the
      app is family-friendly. Apple's stance: photo input is too risky
      for under-12 supervision
- [ ] If kids are a user segment, mention them in the **App Description**
      but position as "general audience also enjoyed by..." rather
      than "designed for children"

### B. Privacy & Consent

- [ ] **First-launch consent screen** if the app touches any user
      data (camera, photo library, contacts, location)
  - Full-screen, not modal (Apple rejects easily-dismissed modals)
  - Two explicit actions: Accept / Decline. No "X to close"
  - On decline, route to a friendly "consent needed" screen, NOT a
    blank scaffold (5.1.1 rejection risk)
  - No network calls before consent is accepted — gate the
    `MaterialApp.builder` / iOS `application(didFinishLaunching)`
- [ ] **Privacy Policy URL** in:
  - ASC → App Information → Privacy Policy URL (must be real, not 404)
  - In-app Settings → Privacy Policy (functional link)
  - Inside the IAP / subscription screen (3.1.2 requirement)
- [ ] **Privacy Policy content** covers (regardless of whether you
      actually collect):
  - Data categories handled
  - On-device vs server processing (state it explicitly)
  - Children (GDPR Art. 8 + COPPA §312.4) — keep this section even
    if you don't target kids. It's required boilerplate
  - Contact email
  - Last-updated date
- [ ] **App Privacy nutrition label** (ASC → App Privacy questionnaire)
      filled honestly. "Data Not Collected" is acceptable when true
      and matches your privacy policy

### C. Permissions (Info.plist usage strings)

- [ ] Every `NS*UsageDescription` you reference is in Info.plist,
      otherwise iOS crashes when the permission is requested
- [ ] Usage strings are **specific** — Apple rejects vague text like
      "for app functionality". Say what the permission is used for in
      a single concrete sentence
- [ ] **Localized** per supported language in `<lang>.lproj/InfoPlist.strings`
      files registered in pbxproj. English-only is technically OK but
      App Store metadata page will show "Supports English" only

### D. In-App Purchase / Subscriptions (3.1.2)

The highest-rejection-rate section. Apple requires ALL of the
following ON THE BUY SCREEN, not buried elsewhere:

- [ ] Subscription **title** (matches IAP product display name)
- [ ] Subscription **length** ("Monthly", "1 Year", or duration in
      the period unit)
- [ ] Subscription **price**, including per-unit if applicable ($X/mo)
- [ ] **Auto-renewal disclosure**: that subscription auto-renews 24h
      before period end at the listed price unless cancelled in App
      Store settings
- [ ] **Cancellation path** mentioned: "Manage in App Store → Apple
      ID → Subscriptions"
- [ ] Functional **Privacy Policy** link
- [ ] Functional **Terms of Use (EULA)** link

For EULA: link to Apple's Standard Auto-Renewable Subscription EULA
unless you draft a custom one. URL:
```
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```
In ASC: leave the EULA field set to Apple Standard (default) unless
you upload custom.

Also include both URLs in the **App Description** (some reviewers
miss the in-app ones and check there).

Additional IAP requirements:
- [ ] **"Manage Subscription"** button in-app that deep-links to
      `https://apps.apple.com/account/subscriptions` (iOS) and
      `https://play.google.com/store/account/subscriptions` (Android)
- [ ] **"Restore Purchases"** button on the paywall — required for
      reinstall / device-switch users
- [ ] Sandbox testing done end-to-end: buy, expire, cancel, restore

### E. Account Deletion (5.1.1(v))

Required if your app has ANY account system, signup, or persistent
login. Also required for offline apps that maintain identity state
(local user IDs, persistent preferences that survive uninstall).

- [ ] Settings → "Delete my data" / "Delete account" — visible, not
      buried in submenus
- [ ] Confirmation dialog with destructive button styled red
- [ ] Wipes EVERYTHING locally: shared_preferences / NSUserDefaults,
      keychain entries, cached files, in-memory state
- [ ] Server-side deletion if applicable
- [ ] After wipe, reset consent state so the app re-shows the consent
      screen (Apple checks this)

### F. Apple Watch / iPad / Universal app

- [ ] If the binary supports iPad, you must submit iPad screenshots
- [ ] If the binary supports Apple Watch, you must submit Watch
      screenshots (all 6 sizes, see app-store-screenshots skill)
- [ ] If you DON'T support a device class, set
      `UIDeviceFamily` correctly in Info.plist so Apple doesn't expect
      screenshots for it

### G. Screenshots

- [ ] **6.9"** iPhone (1320×2868) — required since iOS 18
- [ ] **6.5"** iPhone (1284×2778) — required
- [ ] **iPad 13"** (2064×2752) — required if universal app
- [ ] PNG **without alpha channel** — RGBA causes "screenshot rejected"
      (flatten to RGB / composite onto black before upload)
- [ ] No marketing-only screenshots that don't show actual app UI
- [ ] No "Coming Soon" / placeholder content

### H. Build number

- [ ] **Monotonically increases** between submissions for the same
      version. Even a recalled / rejected build "burns" its number;
      next attempt must be higher
- [ ] Format: integer (e.g. `1.0.0+3`). Apple sees `CFBundleVersion`

### I. Demo Account / Review Notes

- [ ] If your app has login: provide a **Demo Account** in ASC →
      App Review Information, otherwise Apple rejects 2.1
- [ ] If account-free: write "Demo Account: not required — the app
      has no account system" in Notes
- [ ] Always list the IAP product IDs in Notes so reviewer can find
      them quickly
- [ ] Always link Privacy Policy and EULA in Notes too — reviewers
      DO miss the in-app links sometimes

## Common Rejections — Decoder

When the email arrives, look up the Guideline number, not the prose.

| Guideline | What it means | Fast fix |
|---|---|---|
| **1.3 Kids Category** | App in Kids cat but Apple thinks it's not | Switch primary category to Entertainment/Photo & Video, untick "Made for Kids". Photo apps **never** allowed in Kids |
| **2.1 App Completeness** | Build crashed / feature broken / missing demo account | Test on a fresh device. Provide demo creds in Notes. Don't ship beta features behind feature flags during review |
| **2.3.10 Marketing in description** | App Description has placeholder, dates, or pricing claims | Strip "coming soon", remove version numbers from copy. Don't mention "free download" |
| **3.1.1 Use IAP for digital** | You're using Stripe / web link for digital content unlock | Switch to IAP, OR add a "Sign In on Web" disclaimer + no in-app purchase button |
| **3.1.2(a) Auto-renew disclosure** | Subscription terms not on buy screen | Add the full disclosure block (title/length/price/auto-renew/cancel path) inline on the paywall |
| **3.1.2(c) Subscription metadata** | EULA + Privacy links missing | Add both functional links on the paywall AND in the App Description |
| **3.1.3(b) Multiplatform Services** | Cross-platform sub doesn't honor iOS-bought entitlement | Restore Purchases must work; sub state must match across platforms |
| **4.0 Design quality** | "Doesn't meet Apple's quality bar" — usually means the app looks rushed | Polish the home screen icon, splash, first-screen typography. This is subjective |
| **4.3 Spam** | Reviewer thinks you're a clone or thin app | Add value clearly in the first 3 seconds. Update Description to lead with the unique mechanic |
| **5.1.1 Privacy** | Permission missing / vague usage string / privacy policy missing | Audit Info.plist usage strings + ASC Privacy URL + in-app link |
| **5.1.1(v) Account deletion** | App has account but no in-app delete | Add Settings → Delete my data flow |
| **5.1.2 Data sharing** | App Privacy questionnaire doesn't match what app actually does | Reconcile questionnaire honestly; mismatch is detected by static analysis |
| **5.3.4 Demo account required** | Login app without test creds | Provide creds in ASC App Review Notes |

## Resolution Center Reply Template

When Apple rejects, reply in the in-product Resolution Center, not
email. Structure:

```
Hi App Review,

Thank you for the feedback. Build {version} ({build}) addresses the
finding{s}.

1) Guideline {X.Y.Z} — {short topic}
[One paragraph: what you changed. Reference the exact UI surface
or ASC field that was updated. Cite line counts / settings if
relevant.]

[Optional: if the reviewer's interpretation is wrong, explain WHY
your implementation is compliant — but never just argue. Always pair
"here's why this was actually OK" with "and also we made it more
obvious by doing X".]

[Optional: for legal boilerplate like GDPR/COPPA, cite the regulation
that requires it. Apple does respect citations.]

Happy to provide a screen recording on request.

Thanks,
{your name / company}
```

Tone:
- **Polite but specific**. Vague "we improved the experience" replies
  get a re-rejection
- **Cite the exact UI change**. "We added Terms of Use to the Pro
  screen" not "we addressed your concern"
- **Don't argue without conceding ground**. Even when Apple is wrong,
  add a defensive change so the next reviewer doesn't repeat the
  same mistake

## Pre-flight Quick Test

Before the FIRST submission, run this 5-minute test on a real device:

1. **Delete the app** completely, then install fresh
2. **First launch**: consent screen shows, accepting routes to home
3. **Permissions**: trigger each one (camera / photo library) — system
   prompt shows your localized string, not the default
4. **IAP**: open the paywall — title, length, price, auto-renew text,
   Privacy link, Terms link all visible WITHOUT scrolling
5. **Restore Purchases**: tap — completes without crashing
6. **Manage Subscription**: tap — deep-links to system settings
7. **Settings → Delete my data**: tap — confirmation dialog, wipes
   state, returns to consent screen
8. **Background → foreground**: no crash
9. **Airplane mode → launch**: app works offline (if offline-first)

If any step fails, fix BEFORE submitting. App Review will catch it
and you lose 1-3 days.

## Build numbering

- ASC requires `CFBundleVersion` (build number) to monotonically
  increase per version
- Rejected builds burn their number — Build 2 was rejected? Submit
  Build 3, not Build 2 again
- Version (`CFBundleShortVersionString`) can stay the same (1.0.0)
  while bumping build numbers (1, 2, 3, ...) until approval
- After release, bumping version to 1.0.1 lets you start build
  numbering over (but conventionally just keep incrementing)

## After Approval

- **App Store Server Notifications v2**: register your endpoint so
  Apple notifies you of refunds, expirations, renewals (server
  required, but useful for analytics even if entitlement is
  client-validated)
- **Phased Release**: turn ON for the first launch to roll out over
  7 days — catches crashes before 100% of users hit them
- **TestFlight external testing**: keep your test groups warm for
  the next version
- **Promo Codes**: 100 per quarter, for press / reviewers / friends

## Useful URLs

| Need | URL |
|---|---|
| Apple Standard EULA | https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ |
| Manage iOS Subscriptions | https://apps.apple.com/account/subscriptions |
| Manage Android Subscriptions | https://play.google.com/store/account/subscriptions |
| App Store Review Guidelines | https://developer.apple.com/app-store/review/guidelines/ |
| ASC Resolution Center | App Store Connect → My Apps → {app} → Resolution Center |
| App Privacy questionnaire | App Store Connect → {app} → App Privacy |
| Sandbox tester management | App Store Connect → Users and Access → Sandbox → Testers |

## Anti-patterns (Don't)

| Don't | Because |
|---|---|
| Ship features behind a Pro paywall that are not in the IAP product Review screenshot | Reviewer can't validate; auto-rejection |
| Use `print("Pro unlocked")` as your validation | Static analysis detects; 2.1 rejection |
| Skip the consent screen on EU users | GDPR Article 6 — Apple flags via app metadata |
| Have a "delete data" button that doesn't actually delete | Reviewer tests it. Always wipe FOR REAL |
| Submit screenshots that don't match the actual app | 2.3.3 rejection |
| Hide the cancel path for subscriptions | 3.1.2(c) rejection guaranteed |
| Use "free trial" text without a properly-configured introductory offer | 3.1.2(b) rejection |
| Reference a Stripe / web checkout URL in the app for digital goods | 3.1.1 rejection |
| Show different prices in the app vs ASC | Price source-of-truth is ASC; app must use `ProductDetails.price`, not hardcoded |
| Forget to bump build number after rejection | "Build version already exists" — must re-archive |

## Skills That Pair Well

- `app-store-screenshots` — generate compliant marketing screenshots
- `update-config` — Claude Code settings for review-related shell
  automations

## TL;DR

Four guidelines cover ~80% of rejections: **1.3** (Kids Category),
**3.1.2** (subscriptions + EULA), **5.1.1** (privacy / consent /
deletion), **2.1** (demo account + completeness). Get those four
bullet-proof, ship.
