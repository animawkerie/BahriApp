# MultiModal Behavioral Biometrics Data Collection App (BahriApp)
The BahriApp project aimed to collect comprehensive behavioral data of mobile phone users from a mobile application.This repository contains both the user side mobile Application and the backoffice side control of the data being collected.  
# BahriApp

**An Android-based, multimodal behavioral biometric dataset acquisition platform**

BahriApp is an open-source research platform for collecting behavioral
biometric data — the subconscious, habitual patterns in how people type,
swipe, tap, write, and move — through gamified mobile tasks. It captures
**eleven concurrent behavioral modalities** in a single application,
including the first native support for **Amharic (Ge'ez script) keystroke
dynamics**, and ships with **BahriAdmin**, a companion dashboard for
monitoring, filtering, and exporting collected datasets.

**This is a single Flutter codebase that ships two experiences from one
`lib/`:** BahriApp (compiled for Android/iOS, used by participants to play
data-collection games) and BahriAdmin, a.k.a. "BackOffice" (compiled for
Web/Windows/macOS/Linux, used by researchers to monitor collection and
export datasets). There is no separate admin server or Node.js project —
both apps share the same Firebase backend, models, and (where applicable)
widgets, and are differentiated by platform/entry point at build time.

| Component | Description | Build targets |
|---|---|---|
| **BahriApp** | Participant-facing gamified data-collection client | `android`, `ios` |
| **BahriAdmin** (BackOffice) | Researcher-facing monitoring & export dashboard | `web`, `windows`, `macos`, `linux` |

> If your repo instead uses two distinct entry-point files (e.g.
> `lib/main.dart` for BahriApp and `lib/main_admin.dart` for BahriAdmin), or
> Flutter build flavors, adjust the "Running" commands below to match —
> the sections here assume platform-based routing from a single
> `lib/main.dart`.

---

## Table of contents

- [Why BahriApp](#why-bahriapp)
- [Key features](#key-features)
- [System architecture](#system-architecture)
- [Repository structure](#repository-structure)
- [BahriApp — mobile data collection client](#bahriapp--mobile-data-collection-client)
  - [Modalities collected](#modalities-collected)
  - [Requirements](#bahriapp-requirements)
  - [Setup and installation](#bahriapp-setup-and-installation)
  - [Configuration](#bahriapp-configuration)
  - [Running the app](#running-the-app)
  - [Offline mode and data sync](#offline-mode-and-data-sync)
- [BahriAdmin — research dashboard](#bahriadmin--research-dashboard)
  - [Requirements](#bahriadmin-requirements)
  - [Setup and installation](#bahriadmin-setup-and-installation)
  - [Configuration](#bahriadmin-configuration)
  - [Using the dashboard](#using-the-dashboard)
  - [Exporting datasets](#exporting-datasets)
- [Data schema overview](#data-schema-overview)
- [Privacy, consent, and security](#privacy-consent-and-security)
- [Citation](#citation)
- [Contributing](#contributing)
- [Support](#support)
- [License](#license)

---

## Why BahriApp

Existing behavioral biometric data-collection tools tend to suffer from two
gaps: they are built almost exclusively around Latin-script input, and they
typically capture only a handful of modalities at once. BahriApp addresses
both by combining bilingual (English/Amharic) keystroke capture, touch
gestures, handwriting trajectories, and inertial gait/gyroscope sensing in
one gamified application, with production-grade privacy and offline-first
sync built in from the start.

## Key features

- 🎮 **13 gamified tasks across 6 categories** — data collection is embedded
  in short competitive games rather than tedious measurement protocols.
- ⌨️ **Bilingual keystroke dynamics** — fixed-text, password, and free-text
  typing tasks captured in parallel in English and Amharic.
- ✋ **Touch, swipe, and handwriting capture** — including native SVG
  handwriting-stroke trajectories (not rasterized images).
- 📱 **Inertial gait and gyroscope sensing** — walking, jogging, and
  stair-climbing signatures, plus a tilt-controlled balance game.
- 🏆 **Live leaderboards and team competition** — individual and team
  scoring to sustain long-term participant engagement.
- 🔒 **End-to-end encryption** — data is encrypted at rest, in transit, and
  at the edge; minimal-demographic collection with granular consent.
- 📶 **Offline-first sync** — an on-device encrypted cache (Hive) queues
  data locally and batch-syncs automatically once connectivity returns.
- 📊 **BahriAdmin dashboard** — filter, monitor, and export any combination
  of the eleven behavioral datasets to ML-ready CSV.

## System architecture

BahriApp is organized as seven cooperative subsystems spanning the mobile
client, cloud backend, and administrative tooling:

1. **Presentation Layer** — the Flutter mobile UI (registration,
   authentication, game selection, leaderboards).
2. **Game Engine Subsystem** — deterministic game logic, scoring, and state
   transitions; streams raw interaction events to the ingestion pipeline.
3. **Multimodal Acquisition Subsystem** — validates and canonicalizes each
   incoming stream and routes it to Firebase Firestore.
4. **Team and Performance Analytics Subsystem** — team lifecycle,
   role-based access control, real-time scoring.
5. **Common Services and Security Subsystem** — authentication/authorization,
   API gateway, notifications, centralized logging.
6. **BahriAdmin (administrative dashboard)** — export and monitoring
   interface for researchers.
7. **External integrations** — AWS EC2 (application hosting), AWS S3 (cold
   storage snapshots), transactional email, audit logging.

```
Single Flutter Codebase (lib/)
   │
   ├── Build: android / ios  →  BahriApp (participant client)
   │        │
   │        ├── Game Engine ──► Local Hive cache (offline queue, encrypted)
   │        │                         │
   │        │                         ▼
   │        └── Auth/API Gateway ──► Firebase Firestore (live ingestion)
   │                                       │
   │                                       ▼
   │                             AWS S3 (daily cold-storage snapshots)
   │                                       │
   └── Build: web / windows / macos / linux → BahriAdmin / BackOffice ◄──┘
                (dashboard, monitoring, CSV export)
```

## Repository structure

This is a single Flutter project with multi-platform build targets; both
BahriApp and BahriAdmin are compiled from the same `lib/` directory:

```
BahriApp-and-BackOffice/
├── android/                     # Android build target → BahriApp (participant client)
├── ios/                         # iOS build target → BahriApp (participant client)
├── web/                         # Web build target → BahriAdmin/BackOffice dashboard
├── windows/                     # Windows desktop build target → BahriAdmin/BackOffice
├── macos/                       # macOS desktop build target → BahriAdmin/BackOffice
├── linux/                       # Linux desktop build target → BahriAdmin/BackOffice
├── lib/                         # Shared Dart source (UI, game engine, models, services)
├── assets/                      # Fonts, images, Amharic keyboard layout, game assets
├── test/                        # Unit/widget tests
├── build/                       # Build output (git-ignored)
├── docs/                        # Additional documentation (e.g. data-dictionary.md)
├── .env                         # Local environment variables (git-ignored — do not commit real values)
├── .gitignore
├── .metadata                    # Flutter tooling metadata (auto-generated, do not edit by hand)
├── analysis_options.yaml        # Dart/Flutter lint rules
├── devtools_options.yaml        # Flutter DevTools configuration
├── firebase.json                # Firebase project/platform configuration
├── flutter_launcher_icons.yaml  # App icon generation config
├── flutter_native_splash.yaml   # Splash screen generation config
├── pubspec.yaml                 # Package manifest and dependencies
├── pubspec.lock
├── CONTRIBUTING.md
├── LICENSE.txt
└── README.md                    # this file
```

> This tree mirrors the actual project layout. If your `lib/` folder
> organizes BahriApp and BahriAdmin code into subfolders (e.g.
> `lib/app/` vs `lib/backoffice/`, or `lib/features/<modality>/`), it's
> worth adding a short note here for new contributors — e.g.:
> `lib/features/` (per-modality game logic), `lib/services/` (Firebase,
> Hive, encryption), `lib/backoffice/` (admin-only screens/widgets).

---

## BahriApp — mobile data collection client

### Modalities collected

| # | Modality | Description |
|---|---|---|
| 1 | Fixed-text keystroke (English) | Standardized phrase typing |
| 2 | Fixed-text keystroke (Amharic) | Standardized phrase typing, Ge'ez script |
| 3 | Strong-password keystroke | Uniform high-complexity password entry |
| 4 | Free-text keystroke (English) | Unconstrained composition |
| 5 | Free-text keystroke (Amharic) | Unconstrained composition, Ge'ez script |
| 6 | Touch tap | Rapid target-tapping micro-interactions |
| 7 | Touch swipe (horizontal) | Lateral swipe gestures |
| 8 | Touch swipe (vertical) | Vertical swipe gestures |
| 9 | Handwriting (English) | Finger-traced characters, captured as SVG paths |
| 10 | Handwriting (Amharic) | Finger-traced characters, captured as SVG paths |
| 11 | Gait / inertial (accelerometer + gyroscope) | Walking, jogging, stair-climbing, and a tilt-controlled balance game |

Full metric taxonomies (hold time, flight time, path length, stroke count,
tilt speed, etc.) and formulae for every modality are documented in
[`/docs/data-dictionary.md`](./docs/data-dictionary.md).

### BahriApp requirements

- Android 8.0 (API 26) or higher
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable channel)
- A Firebase project with Firestore enabled
- Android Studio (or VS Code with the Flutter/Dart extensions)
- A physical Android device or emulator with accelerometer/gyroscope
  support for gait and gyroscope tasks

### BahriApp setup and installation

```bash
# 1. Clone the repository
git clone https://github.com/<org>/Mobile-App-for-Multi-Modal-Behavioral-Data-Collection-BahriApp-and-BackOffice.git
cd Mobile-App-for-Multi-Modal-Behavioral-Data-Collection-BahriApp-and-BackOffice

# 2. Install Flutter dependencies (shared by both BahriApp and BahriAdmin)
flutter pub get

# 3. Add your Firebase configuration
#    - firebase.json is already tracked in the repo (non-secret project config)
#    - Place google-services.json in android/app/ (Android)
#    - Place GoogleService-Info.plist in ios/Runner/ (iOS)
#    - Run `flutterfire configure` if you use the FlutterFire CLI to regenerate these

# 4. Run BahriApp on a connected Android device or emulator
flutter run -d <android-device-id>
```

To build a release APK:

```bash
flutter build apk --release
```

### BahriApp configuration

An `.env` file already exists at the project root (git-ignored — never
commit real values). Populate it with:

```
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_API_KEY=your-api-key
API_GATEWAY_URL=https://your-api-gateway-url
ENCRYPTION_KEY_ALIAS=your-android-keystore-alias
```

Icon and splash-screen assets are generated from `flutter_launcher_icons.yaml`
and `flutter_native_splash.yaml` respectively — after changing branding
assets in `/assets`, regenerate them with:

```bash
flutter pub run flutter_launcher_icons
flutter pub run flutter_native_splash:create
```

> Never commit real Firebase credentials, keystores, or API keys. `.env`
> and platform-specific Firebase config files should stay in `.gitignore`
> — only `firebase.json` (non-secret project linkage) is safe to track.

### Running the app

On first launch, participants:

1. Register and complete the informed-consent flow.
2. Select a game category from the main menu (keystroke, swipe/tap,
   handwriting, or gyroscope/gait).
3. Play; all raw interaction telemetry is timestamped, encrypted locally,
   and queued for sync automatically — no manual data submission is
   required.
4. View their live score and team ranking on the in-app leaderboard.

### Offline mode and data sync

BahriApp is designed for low-connectivity field deployments:

- All gameplay works fully offline. Interaction events are encrypted and
  cached locally using [Hive](https://pub.dev/packages/hive).
- When connectivity is restored, the client automatically batch-syncs
  queued events to Firebase Firestore.
- No data is lost or duplicated across sync cycles; each event carries a
  unique client-generated identifier for idempotent writes.

---

## BahriAdmin — research dashboard

BahriAdmin is the companion interface researchers use to monitor data
collection in real time and export datasets for analysis.

BahriAdmin is **not** a separate Node.js project — it's the same Flutter
codebase as BahriApp, built for desktop/web platforms instead of mobile.
This is why the repository includes `web/`, `windows/`, `macos/`, and
`linux/` folders alongside `android/` and `ios/`.

### BahriAdmin requirements

- The same Flutter SDK install used for BahriApp (no additional runtime
  required)
- For web builds: Chrome (or another Chromium-based browser) for local
  development
- For desktop builds: platform build tooling — Visual Studio (Windows
  desktop workload), Xcode (macOS), or the standard Linux desktop toolchain
  (`clang`, `cmake`, `ninja`, GTK development libraries)
- Access credentials to the same Firebase project used by BahriApp
- AWS credentials (read access) if exporting from S3 cold-storage snapshots

### BahriAdmin setup and installation

```bash
# From the same repository root used for BahriApp
flutter pub get

# Enable desktop/web platform support once, if not already enabled
flutter config --enable-web --enable-windows-desktop \
  --enable-macos-desktop --enable-linux-desktop

# Run the dashboard locally in a browser
flutter run -d chrome

# ...or as a native desktop app
flutter run -d windows   # or: macos / linux
```

To build a deployable release:

```bash
flutter build web        # outputs to build/web — deploy to any static host
flutter build windows     # or: macos / linux — produces a native desktop app
```

> If BahriAdmin lives behind a distinct entry point (e.g.
> `flutter run -d chrome -t lib/main_admin.dart`) rather than being
> selected automatically by platform, use that `-t` flag with the commands
> above.

### BahriAdmin configuration

BahriAdmin reads the same `.env`/Firebase configuration as BahriApp, plus
whatever AWS credentials it needs for S3 exports:

```
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_SERVICE_ACCOUNT_KEY=path/to/service-account.json   # server-side export jobs only, if applicable
AWS_ACCESS_KEY_ID=your-aws-key
AWS_SECRET_ACCESS_KEY=your-aws-secret
AWS_S3_BUCKET=your-cold-storage-bucket
```

> As with BahriApp, keep all real credentials out of version control —
> `.env` is already git-ignored in this repository.

Administrator accounts and role-based access are managed through Firebase
Authentication. To add a new administrator:

1. Create the user in the Firebase Authentication console.
2. Add their UID to the `admins` collection in Firestore.
3. Assign a role (`super_admin`, `team_admin`, or `viewer`) as needed.

### Using the dashboard

BahriAdmin provides:

- **Summary metrics** — total records, records per modality, top
  contributing users, and collection completeness at a glance.
- **Team management** — view team rosters, cumulative team scores, and
  historical game distributions.
- **Session tracking** — per-user session counts across all eleven
  modalities.
- **Filter panels** — narrow the view by date range, institution, modality,
  or team before exporting.

### Exporting datasets

1. Open **Dashboard → Filter Panels** and select the modality(ies), date
   range, and/or cohort you need.
2. Click **Export to CSV**.
3. The exported file(s) use the schema documented in
   [`/docs/data-dictionary.md`](./docs/data-dictionary.md), ready for
   direct ingestion into pandas, R, or your ML pipeline of choice.

---

## Data schema overview

Each modality is stored as its own Firestore collection (and, on export, a
separate CSV) with a shared set of identifying fields:

| Field | Description |
|---|---|
| `user_id` | Anonymized participant identifier |
| `session_id` | Unique session identifier |
| `team_id` | Team affiliation, if applicable |
| `timestamp` | ISO-8601 event or session timestamp |
| `language` | `en` or `am`, where applicable |
| `modality` | One of the eleven modality identifiers |
| `...` | Modality-specific fields (see data dictionary) |

See [`/docs/data-dictionary.md`](./docs/data-dictionary.md) for the
complete, per-modality field reference (basic, engineered, and
screen/session-normalized features).

## Privacy, consent, and security

- Participants complete a mandatory informed-consent flow before any
  background sensor stream is activated.
- Only minimal demographic data is collected (age range and gender), never
  direct identifiers.
- All interaction data is encrypted **at rest**, **in transit**, and **at
  the edge** (on-device, prior to sync).
- Administrative data access is logged through an immutable audit-logging
  service.
- If you deploy BahriApp for your own research, ensure you obtain
  appropriate institutional ethics/IRB approval before collecting data
  from human participants.

## Citation

If you use BahriApp or BahriAdmin in your research, please cite:

```bibtex
@article{aseres2026bahriapp,
  title   = {BahriApp: An Android-Based Multimodal Behavioral Biometric Dataset Acquisition Platform},
  author  = {Aseres, Animaw Kerie and Beyene, Asrat Mulatu and Tegegne, Lemlem Kassa and Daniel, Wongel Dawit},
  journal = {SoftwareX},
  year    = {2026}
}
```

## Contributing

Contributions are welcome. Please:

1. Open an issue describing the change or bug before submitting a large
   pull request.
2. Follow the existing code style — run `flutter format .` and
   `flutter analyze` (rules defined in `analysis_options.yaml`) before
   submitting.
3. Add or update tests in `/test` where applicable.
4. Submit a pull request against `main` with a clear description of the
   change, noting whether it affects BahriApp (mobile), BahriAdmin
   (desktop/web), or shared code in `lib/`.

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for full guidelines.

## Support

For questions, please open a
[GitHub issue](https://github.com/<org>/Mobile-App-for-Multi-Modal-Behavioral-Data-Collection-BahriApp-and-BackOffice/issues)
or contact the corresponding author at **animaw.kerie@kue.edu.et**.

## License

This project is licensed under the **[INSERT CHOSEN LICENSE — e.g., MIT
License]**. See [`LICENSE.txt`](./LICENSE.txt) for the full text.
