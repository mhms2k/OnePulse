# OpenPulse

A WHOOP-style recovery, strain and sleep coach for the wearable you already own.
OpenPulse talks to devices **directly over Bluetooth** (no Nothing X, no Apple Health in between),
stores everything **on the iPhone**, and turns raw data into three daily scores plus plain-language feedback.

| Score | Scale | Built from |
|---|---|---|
| **Recovery** | 1–99 % (green / yellow / red) | HRV (or the watch's overnight stress index), resting HR, sleep performance, SpO₂ — each vs. *your* 30-day baseline |
| **Strain** | 0–21 (logarithmic) | Banister TRIMP on heart-rate reserve, with a time-in-zone breakdown |
| **Sleep** | performance % | Hours asleep ÷ sleep need (baseline + strain + debt − naps), plus stages, efficiency, consistency |

### Also included (v1.1)

| Feature | What it does |
|---|---|
| **Healthspan** | Body age and pace of aging from 30 days of VO₂ max (estimated), resting HR, sleep hours & consistency, zone 1–3 / 4–5 minutes, strength time and steps |
| **Stress monitor** | 0–3 stress through the day (watch stress index, or heart rate vs. resting HR), workouts excluded |
| **Breathwork** | Guided Relax / Focus / Alert breathing sessions with haptics |
| **Journal & behavior insights** | Daily yes/no habits (20 to choose from); after 5 yes + 5 no answers, shows the Recovery difference; 5-week habit calendar |
| **Strength trainer** | Log sets, reps and weight; volume, personal records (est. 1RM) and weekly strength time |
| **Weekly plan & report** | Goals for workouts, strength minutes, sleep and steps; last 7 days vs. the 7 before |
| **Cycle tracking** | Log period starts; shows cycle day, phase and phase-specific guidance |

Not included: the AI assistant, respiratory rate and skin temperature (the CMF watch doesn't expose them), haptic alarms, ECG, teams.

## Supported devices

| Device | How | Data |
|---|---|---|
| CMF Watch 3 Pro / Watch Pro 2 / Watch Pro | Proprietary CMF protocol (pairing, AES session, record sync) | Sleep stages, all-day HR, SpO₂, stress, steps, workouts |
| Any Bluetooth heart-rate sensor (Polar, Garmin, Wahoo, Coros, Amazfit, …) | Standard Heart Rate Profile (0x180D) | Live HR, beat-to-beat RR → true HRV (RMSSD) |

New brands are added by writing one `WearableDriver` subclass (see *Architecture*).

## Build and run

You need a Mac with **Xcode 16 or newer** and an iPhone on **iOS 17+**. A free Apple ID is enough to install on your own phone
(apps signed with a free account must be re-installed every 7 days).

1. Open `OpenPulse.xcodeproj`.
2. Select the **OpenPulse** target → *Signing & Capabilities* → choose your **Team**. If Xcode complains about the bundle ID,
   change `app.openpulse.OpenPulse` to something unique, e.g. `com.yourname.openpulse`.
3. **Simulator:** press ▶︎, finish onboarding and tap *Try it with demo data first*. Every screen works with six weeks of
   generated data. (Bluetooth does not exist in the simulator.)
4. **iPhone:** plug it in, select it as the run destination and press ▶︎. The first time, trust the developer under
   *Settings › General › VPN & Device Management*.
5. **Tests:** `⌘U` runs the unit tests (protocol vectors checked against an independent Python implementation, HR/HRV
   parsing, and the scoring engine).

## Building without a Mac

Every push runs `.github/workflows/ios.yml` on a GitHub-hosted Mac. It builds the app with code signing switched off,
then runs the unit tests.

1. On GitHub, open **Actions** → the latest green **iOS build** run → **Artifacts** → download **OpenPulse-unsigned-ipa**
   (a zip that contains `OpenPulse-unsigned.ipa`).
2. On a Windows PC, install [Sideloadly](https://sideloadly.io), plus the *website* versions of iTunes and iCloud (not the
   Microsoft Store versions).
3. Connect the iPhone by USB, drag the `.ipa` into Sideloadly, sign in with your Apple ID and press **Start**.
4. On the iPhone, enable **Settings › Privacy & Security › Developer Mode** (iOS 16+). Then trust your Apple ID under
   **Settings › General › VPN & Device Management**.
5. With a free Apple ID the app expires after **7 days**. Re-sign it with Sideloadly; its auto-refresh can do this over Wi-Fi.

CI minutes: public repositories get unlimited macOS minutes. Private repositories on the free plan get about 190 macOS
minutes a month (about 15 runs of this workflow).

## Pairing the CMF Watch 3 Pro

A watch can only talk to one app at a time.

1. In the **Nothing X** app, remove the watch. Then in **iPhone Settings › Bluetooth**, tap ⓘ next to the watch → *Forget This Device*.
2. Restart the watch (or factory-reset it if pairing fails).
3. In OpenPulse: **Devices → Add a device**, wait for *CMF Watch 3 Pro*, tap it.
4. OpenPulse asks the watch for its pairing secret, performs the SHA-256 handshake and stores the key in the Keychain.
   It then sets the clock, turns on all-day HR / SpO₂ / stress monitoring and pulls all recorded data.
5. Wear the watch to sleep. Recovery unlocks after **4 nights** (it needs your personal baseline).

The app re-syncs every 30 minutes while connected, when the watch asks for it, on pull-to-refresh, and each time the app opens.

**If pairing fails**, open *Devices → Bluetooth log*, tap share, and send the log. Every packet is logged in hex, which
is exactly what's needed to adapt to a new firmware.

## How the scores work

**Recovery.** Each morning, the night's inputs become z-scores against your trailing 30-day baseline (minimum 4 nights):
autonomic signal 50 % (HRV RMSSD, log-scaled; or −stress when the device has no beat-to-beat data), resting HR 30 %
(mean of the lowest quartile of sleeping HR), sleep performance 20 %, SpO₂ 10 % (penalty only). The weighted composite
goes through a logistic curve → 1–99 %. Green ≥ 67, yellow 34–66, red ≤ 33. Today's strain target follows: 14–18 / 10–14 / <10.

**Strain.** For every heart-rate sample (each standing for the time until the next, capped at 10 min):
`HRR = (HR − RHR) / (HRmax − RHR)`; load `+= minutes × HRR × 0.64·e^(1.92·HRR)` (female: 0.86·e^(1.67·HRR)) when
HRR ≥ 0.25. Day strain = `21 × (1 − e^(−TRIMP/150))`. HRmax defaults to 208 − 0.7 × age and can be set in Profile.

**Sleep need.** Baseline (default 7 h 45 m) + up to 50 min for yesterday's strain above 8 + weighted shortfall of the
last three nights vs. baseline + strain (50 / 25 / 12.5 %, capped at 3 h, so debt never compounds) − naps. The *Tonight* card turns that into a bedtime based on your
typical wake time and recent sleep efficiency.

**Coach.** Rule-based feedback on recovery zone, sleep sufficiency, deep/REM share, efficiency, schedule consistency,
elevated resting HR or stress, low HRV, low SpO₂, accumulated load and 7-day vs 30-day trends.

These are wellness estimates, not medical measurements.

## Architecture

```
OpenPulse/
  App/            App entry, tabs, navigation
  Core/           Pure logic (no UI, no database) — unit-tested
    Bytes.swift       ByteReader/Writer, hex, CRC32
    CMF/              CMF protocol: commands, AES/SHA crypto, framing + chunking, pairing, record parsers
    HeartRate/        BLE Heart Rate Measurement (0x2A37) parser, RR cleaning, RMSSD
    Engine/           Health types, ScoreEngine (recovery/strain/sleep), Coach (feedback), stats
  Data/           SwiftData models (deduplicated by key) + HealthStore (ingest → score → publish)
  Devices/        BluetoothManager (scan/connect/restore), WearableDriver base, CMF + HR sensor drivers, Keychain
  DesignSystem/   Theme, rings, cards, shared charts
  Features/       Today, Sleep, Strain, Recovery, Trends, Devices, Profile, Onboarding
  Demo/           Deterministic 6-week demo data generator
OpenPulseTests/   Protocol vectors, HR/HRV parsing, scoring engine
```

**Adding a device:** subclass `WearableDriver`, conform it to `CBPeripheralDelegate`, turn the device's packets into a
`HealthBatch` and `emit(.batch(...))`. Add a `DeviceKind` case and a line in `BluetoothManager.classify` /
`centralManager(_:didConnect:)`. Storage, scoring, charts and feedback work automatically.

## Known limitations

- The CMF Watch 3 Pro does not expose beat-to-beat intervals, so Recovery uses its overnight stress index as the
  autonomic signal. Pair any chest strap or HR armband overnight to get true HRV.
- The CMF resting-heart-rate record format is undocumented; OpenPulse computes resting HR from sleeping heart rate
  instead, and logs the raw records for decoding.
- Watch 3 Pro support relies on the community's reverse-engineering (the same protocol as the Watch Pro 2). A firmware
  update from Nothing could change it — the Bluetooth log makes that quick to diagnose.

## Credits

CMF protocol knowledge comes from the open-source [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge)
project's reverse-engineering work. OpenPulse is an independent Swift implementation of that protocol description.
