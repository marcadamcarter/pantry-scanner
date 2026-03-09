# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS app for barcode scanning, expiration-date tracking, and pantry inventory management. Built in Swift/SwiftUI, delivered to TestFlight via Codemagic CI/CD.

## Build & Run

Requires a Mac with Xcode.

```bash
open PantryScanner/Pantry.xcodeproj
# Xcode → Product → Run (simulator or device)
```

- **Bundle ID**: `com.northpadreisles.PantryScanner`
- **Xcode scheme**: `SimpleNews`
- **Development Team**: `R8R77PB278`

## CI/CD (Codemagic)

Pipeline defined in `codemagic.yaml`. On push:
1. Installs Apple Distribution certificate from Codemagic secure storage
2. Fetches/creates App Store provisioning profile for the bundle ID
3. Builds `.ipa` from `.xcodeproj`
4. Uploads to TestFlight

No secrets in the repo — all signing credentials live in Codemagic dashboard.

## Architecture

- **`PantryScanner/Pantry.xcodeproj`** — Xcode project
- **`codemagic.yaml`** — CI/CD workflow (build, sign, deploy to TestFlight)
