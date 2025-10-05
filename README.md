# 🧺 Pantry Scanner (iOS)

A lightweight iOS app to **scan barcodes**, track **expiration dates**, and keep a tidy pantry. Built in Swift/SwiftUI and delivered to TestFlight via **Codemagic CI/CD**.

---

## Features

- 📷 Fast barcode scanning
- ⏳ Expiration-date tracking and reminders
- 🗂️ Simple inventory views (by item/category/expiring soon)
- 📴 Works offline; sync-ready design
- 🔒 iOS-first, privacy-conscious

---

## Tech Stack

| Area            | Choice                                     |
|-----------------|--------------------------------------------|
| Platform        | iOS (Swift / SwiftUI)                      |
| Build           | Xcode                                      |
| CI/CD           | Codemagic                                  |
| Signing         | Apple Distribution certificate + profiles  |
| Bundle ID       | `com.northpadreisles.PantryScanner`        |

---

## Repository

```
.
├── PantryScanner\Pantry.xcodeproj
├── codemagic.yaml
├── README.md
└── (source files…)
```

---

## Getting Started (Local Xcode)

> You’ll need a Mac with Xcode if building locally. CI/CD via Codemagic does not require you to own a Mac.

1. Clone:
   ```bash
   git clone https://github.com/marcadamcarter/pantry-scanner.git
   cd pantry-scanner
   ```
2. Open in Xcode:
   ```bash
   open PantryScanner.xcodeproj
   ```
3. Target ➜ **Signing & Capabilities** (Release):
   - Team: your Apple team
   - **Automatically manage signing**: ON
4. Run on a simulator or device.

---

## CI/CD with Codemagic

- Workflow file: [`codemagic.yaml`](./codemagic.yaml)
- What the pipeline does:
  - Installs the Apple Distribution **certificate** from Codemagic’s secure storage
  - Fetches/creates a matching **App Store** provisioning profile for `com.northpadreisles.PantryScanner`
  - Builds an **.ipa** from the **.xcodeproj**
  - (Optionally) uploads to **TestFlight**

### Required Codemagic setup (one-time)

- **Teams → Integrations → App Store Connect**: add your ASC API key (tied to the correct Apple Team)
- **Teams → Code signing identities**:
  - Upload or generate an **Apple Distribution** certificate (e.g., `PantryScannerDistCert`)
  - (Optional) Upload a manually created **iOS App Store** provisioning profile for the bundle ID

> No secrets are stored in the repository; they live in Codemagic.

---

## Roadmap

- Product lookup/auto-fill from barcode
- Smarter “use soon” suggestions
- iCloud sync
- Home Screen widgets for quick adds/expiring soon

---

## License

MIT — see [`LICENSE`](./LICENSE) (or choose a license and update this line).

