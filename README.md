# BillHive iOS App

Native SwiftUI iOS app for [BillHive](https://github.com/martyportatoes/billflow) — self-hosted household bill management.

## Requirements

- **Xcode 15+**
- **iOS 16.0+** (uses Swift Charts)
- A running [BillHive server](https://github.com/martyportatoes/billflow)

## Opening in Xcode

```bash
open BillHive.xcodeproj
```

Then select your target device/simulator and press **⌘R** to run.

## First Launch

On first launch, you'll see a **Server Setup** screen. Enter the base URL of your self-hosted BillHive instance:

```
http://192.168.1.100:8080
```

or if behind a reverse proxy:

```
https://bills.yourdomain.com
```

The app will test the connection before saving. Once connected, all your existing bills, people, and monthly data will load automatically.

## Features

| Tab | Description |
|---|---|
| 📋 Bills | Enter monthly amounts for each bill. Supports % and fixed splits. |
| 💰 Summary | See what each person owes this month, plus your total outlay. |
| 📤 Send & Receive | Email summaries, Zelle/Venmo payment links, monthly checklist. |
| 📈 Trends | Month-over-month charts (line, donut, stacked bar) via Swift Charts. |
| ⚙️ Settings | Manage people, payment methods, email relay, bill config, data export. |

## Architecture

```
BillHive/
├── BillHiveApp.swift          # App entry point
├── Models/
│   ├── Person.swift           # Person + PayMethod models
│   ├── Bill.swift             # Bill + BillLine models
│   ├── MonthData.swift        # Monthly data, AppState, MonthKey helpers
│   └── EmailConfig.swift      # Email provider config
├── Network/
│   └── APIClient.swift        # URLSession-based REST client
├── ViewModels/
│   └── AppViewModel.swift     # Central state + business logic
└── Views/
    ├── ContentView.swift       # TabView root + ToastView + design tokens
    ├── ServerSetupView.swift   # First-launch server configuration
    ├── BillsView.swift         # Bills tab
    ├── SummaryView.swift       # Summary tab
    ├── SendReceiveView.swift   # Send & Receive tab
    ├── TrendsView.swift        # Trends tab (Swift Charts)
    └── SettingsView.swift      # Settings tab
```

## Network Security

The app connects to your local/private BillHive server over HTTP or HTTPS. Since servers may be on a local network without a trusted certificate, `NSAllowsArbitraryLoads` is set to `true` in the generated Info.plist. For production use behind a reverse proxy with a valid TLS certificate, you may restrict this.

## Changing Server

Go to **Settings → Server** and tap **Change** to update the server URL. The app will reconnect and reload all data.
