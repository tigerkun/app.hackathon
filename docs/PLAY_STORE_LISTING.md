# Google Play Console Store Listing & Data Safety Kit

Prepared from verified SafeSphere source (`frontend/pubspec.yaml`, `AndroidManifest.xml`, `backend/src/views/privacyPolicyPage.js`, and live Render deployment).

---

## 1. App Identity & Artifacts

- **Application ID:** `com.example.newhere` (note: update `applicationId` in `frontend/android/app/build.gradle.kts` to a unique reverse-domain package like `app.safesphere.mobile` if publishing publicly on Play Store; `com.example.*` is rejected by Google Play Console on new app upload!)
- **Signed Release AAB:** Build with:
  ```bash
  cd frontend
  flutter build appbundle --release --dart-define=SAFESPHERE_API_URL=https://safesphere-backend-c4fs.onrender.com
  ```
- **Signed Release APK (Sideload):** `frontend/build/app/outputs/flutter-apk/app-release.apk`
- **Privacy Policy URL (live):** `https://safesphere-backend-c4fs.onrender.com/privacy`
- **Support Email:** `tejasgaur94@gmail.com`

---

## 2. Store Listing Copy

- **App Name (max 30 chars):** `SafeSphere`
- **Short Description (max 80 chars):**
  `Personal SOS alerts, live guardian trip tracking, and verified safety maps.` (77 chars)
- **Full Description:**
  ```
  SafeSphere is an assistive personal-safety and community safety-awareness companion built for rapid help when seconds count.

  KEY CAPABILITIES
  • Immediate Emergency SOS & Helplines: One-tap access to 112, 181 (Women Helpline), 108 (Ambulance), and 101 (Fire Services) — always accessible even without login or internet connectivity.
  • Live Guardian Trip Sharing: Create time-bounded live tracking links Guardians can open in any web browser or in-app, complete with automatic stall detection and missed check-in alerts.
  • My Circle & Privacy Hub: Connect privately using pseudonymous Safe IDs (SF-XXXX-XX) without exposing your phone number or email. Inspect every active sharing channel and revoke access anytime in "Who can see me".
  • Safety Map & Community Alerts: View dark-mode OpenStreetMap hazard reports and verified refuges (Police Posts, Hospitals, 24x7 Stores, Safe Zones) near you, plus vote to confirm or decline reports.
  • Discreet Mode & Hardware Panic Gestures: Mute SOS visuals and launch a realistic Fake Call Screen when discretion matters, plus optional volume-down hold / shake shortcuts.
  • AI Safety Assistant: Calm step-by-step guidance backed by curated offline emergency protocols when signal drops.

  ASSISTIVE SOFTWARE NOTICE
  SafeSphere assists communication and situational awareness. It is NOT a replacement for emergency services (112, 181, 108, 101). Always call 112 directly in urgent peril.
  ```
- **App Category:** `Tools` or `Maps & Navigation` (or `Lifestyle`)
- **Free or Paid:** `Free`, **Contains Ads:** `No`

---

## 3. Data Safety Form Answers (Exact Code Mapping)

- **Does your app collect or share any required user data types?** **Yes**
- **Is all of the user data collected by your app encrypted in transit?** **Yes** (`https://safesphere-backend-c4fs.onrender.com` + `wss://`)
- **Do you provide a way for users to request that their data is deleted?** **Yes**
  - **In-app:** Drawer → *Privacy & Consent (DPDP)* → *Delete My Account* (`DELETE /api/v1/auth/me`)
  - **Delete account URL:** `https://safesphere-backend-c4fs.onrender.com/privacy`

| Play Console Data Type | Collected | Shared | Purpose | Required / Optional | Notes |
|---|---|---|---|---|---|
| **Personal info → Name** | Yes | With verified community reports / guardians you share with | App functionality, Account management | Required (for registered account) | Guests use `/emergency` & `/share` without signing up |
| **Personal info → Email address** | Yes | **No** | App functionality, Account management, Fraud/security (OTP verification) | Required (for registration) | Masked in `/otp/send`; hidden from Safe ID connections |
| **Personal info → Phone number** | Yes | **No** | App functionality, Account management, Fraud/security | Required (for account & emergency contact) | Hidden from Safe ID connections & public reads |
| **Personal info → Other info (Keyed last-4 Aadhaar hash)** | Optional | **No** | Fraud prevention, security, and compliance | Optional (Skippable) | Stored only as keyed HMAC hash (`aadhaarLast4Hash`); never full ID |
| **Location → Precise location** | Yes | Only during user-initiated SOS, `/share` tracking link, or approved Trusted Circle access | App functionality | Optional (manual landmark fallback supported) | No silent background tracking |
| **User-generated content → Photos / App interactions** | Optional | Community Alerts (reports) | App functionality | Optional | Optional report photo ≤500 KB; community up/down votes |
| **Messages → Other in-app messages (SOS responder chat & AI queries)** | Optional | SOS responders in same alert room | App functionality | Optional | SOS chat capped at 50 FIFO msgs; AI prompts sanitized |
| **Financial / Health / Contacts list / Advertising ID** | **No** | **No** | — | — | Not collected |

---

## 4. Content Rating & Store Screenshots Checklist

- **Content Rating (IARC):** No violence/gore/sexual/gambling; assistive safety utility + user-generated safety reports (report moderation & vote-threshold hiding enabled) -> typically **Rated 3+ / Everyone** or **Teen / 12+** due to user-generated community alerts.
- **Phone Screenshots (1080×2400 PNG captured from live app in scratch artifacts):**
  1. Home SOS-First Hero (`live_13_verified_home.png`)
  2. Safety Map with Dark OSM Tiles & Glowing Pins (`live_15_map_delhi.png`)
  3. Community Alerts Feed (`live_19c_alerts.png`)
  4. My Circle Safe ID (`live_20_my_circle.png`)
  5. Privacy Hub "Who can see me" (`live_18_privacy_hub.png`)
  6. AI Safety Assistant (`live_06b_ai_reply.png`)
  7. Discreet Mode & Emergency Info (`live_22_discreet_emerg.png`)
  8. Fake Call Screen (`live_23_fakecall.png`)
- **Feature Graphic (1024×500)** & **High-res Icon (512×512):** Export required before final Play Console Store Listing submission.
