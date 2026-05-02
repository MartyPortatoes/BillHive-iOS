# BillHive iOS

Native SwiftUI companion to [BillHive](https://github.com/MartyPortatoes/BillHive) — household bill management for iPhone and iPad.

The Xcode project ships **two targets** from one codebase:

| Target | What it is | App Store |
|---|---|---|
| **BillHive** | Standalone, iCloud-synced. No server needed. | [Download](https://apps.apple.com/us/app/billhive-bill-splitting/id6759998736) |
| **SelfHive** | Connects to a self-hosted [BillHive server](https://github.com/MartyPortatoes/BillHive). | [Download](https://apps.apple.com/us/app/selfhive-bill-splitting/id6760245713) |

Same views, models, and view model — only the storage/sync layer differs.

## Requirements

- **Xcode 15+**
- **iOS 16.0+** (uses Swift Charts)
- For SelfHive only: a running [BillHive server](https://github.com/MartyPortatoes/BillHive)

## Opening in Xcode

```bash
open BillHive.xcodeproj
```

Pick the `BillHive` or `SelfHive` scheme, select a device/simulator, and press **⌘R**.

## First Launch

**BillHive** — opens straight into the app. Your data lives in iCloud Drive (`iCloud.com.billhive.app/Documents/`) and stays in sync across devices on the same Apple ID.

**SelfHive** — shows a Server Setup screen. Enter the base URL of your self-hosted instance:

```
http://192.168.1.100:8080
```

or behind a reverse proxy with TLS:

```
https://bills.yourdomain.com
```

The app tests the connection before saving. You can also configure a backup URL (e.g. a Tailscale IP) for automatic failover when away from your home network.

**Optional API key (per-device auth)** — generate a key in BillHive web → Settings → Connected Devices, then paste it into SelfHive's Server Setup screen (or later via Settings → Server). The key is stored in iOS Keychain (`WhenUnlockedThisDeviceOnly`), sent as `Authorization: Bearer` on every API request, and never written to UserDefaults or backed up via iCloud. If your server has the **Require API key for iOS apps** toggle on, this is mandatory.

## Features

| Tab | Description |
|---|---|
| Bills | Enter monthly amounts for each bill. Supports % and fixed splits. |
| Summary | See what each person owes this month, plus your total outlay. |
| Pay & Collect | Email summaries, Zelle / Venmo / Cash App payment links, monthly checklist. |
| Trends | Month-over-month charts (line, donut, stacked bar) via Swift Charts. |
| Settings | Manage people, payment methods, email relay, bill config, data export. |

## Architecture

```
BillHive/
├── BillHiveApp.swift              # @main for BillHive target (iCloud)
├── SelfHiveApp.swift              # @main for SelfHive target (server)
├── PurchaseManager.swift          # StoreKit 2 — IAP + 14-day trial
├── Models/
│   ├── Person.swift               # Person + PayMethod
│   ├── Bill.swift                 # Bill + BillLine + SplitType
│   ├── MonthData.swift            # MonthData, AppState, MonthKey
│   └── EmailConfig.swift          # Email provider config
├── Network/
│   └── APIClient.swift            # URLSession REST client (SelfHive)
├── Storage/
│   ├── CloudStorageManager.swift  # iCloud Documents (BillHive)
│   └── LocalStorageManager.swift  # Local Documents fallback
├── ViewModels/
│   └── AppViewModel.swift         # @MainActor state + business logic
└── Views/
    ├── ContentView.swift          # TabView root, design tokens, privacy overlay
    ├── ServerSetupView.swift      # First-launch URL onboarding (SelfHive)
    ├── BillsView.swift
    ├── SummaryView.swift
    ├── SendReceiveView.swift
    ├── TrendsView.swift
    ├── SettingsView.swift
    ├── PaywallView.swift          # IAP / trial gate
    ├── MailComposeView.swift      # iOS Mail compose (BillHive)
    └── HexagonBackground.swift    # Brand background + button styles
```

## Network Security

**BillHive** uses default iOS App Transport Security (HTTPS only) — it never makes outbound HTTP requests, just iCloud and the system Mail compose sheet.

**SelfHive** sets `NSAllowsArbitraryLoads: true` in its Info.plist because users routinely point it at LAN IPs (`192.168.x.x`) or Tailscale CGNAT addresses (`100.x.y.z`) where TLS isn't available. For production use behind a reverse proxy with a real certificate, you can tighten ATS or migrate to Tailscale's MagicDNS HTTPS to remove the exception entirely.

URL handling is hardened: bill payment URLs and custom Zelle URLs are HTTPS-only validated, and Venmo / Cash App deep-link handles are percent-encoded before interpolation.

## Changing the Server (SelfHive)

Go to **Settings → Server** and tap **Change** to update the URL. The app reconnects and reloads all data.
