# BillHive iOS — Claude Code Context

> Native SwiftUI companion to the BillHive web app.
> For project-wide context, see the root `../../CLAUDE.md`.

---

## Overview

Two app targets from one codebase: **BillHive** (iCloud-synced, standalone) and
**SelfHive** (connects to self-hosted BillHive server). Same views, models, and
view model — only the storage/sync layer differs.

**iOS 16+** · **SwiftUI** · **Swift Charts** · **MVVM** · **async/await**

---

## Dual-Target Setup

| | BillHive | SelfHive |
|---|---|---|
| Entry point | `BillHiveApp.swift` | `SelfHiveApp.swift` |
| Storage | iCloud Documents (`CloudStorageManager`) + local fallback | REST API (`APIClient`) |
| First launch | Migrates local → iCloud if needed | Shows `ServerSetupView` for URL entry |
| Email | System `MFMailComposeViewController` | Server-side via `/api/email/send` |
| Entitlements | iCloud containers + CloudDocuments | `NSAllowsArbitraryLoads: true` (local network HTTP) |

---

## File Structure

```
BillHive/
├── BillHiveApp.swift              # iCloud target entry (@main)
├── SelfHiveApp.swift              # Server target entry (@main)
├── Models/
│   ├── Bill.swift                 # Bill, BillLine, SplitType
│   ├── Person.swift               # Person, PayMethod, Color.hex helpers
│   ├── MonthData.swift            # MonthData, AppState, AppSettings, MonthKey
│   └── EmailConfig.swift          # EmailConfig, EmailProvider
├── Network/
│   └── APIClient.swift            # Singleton REST client (@MainActor)
├── Storage/
│   ├── CloudStorageManager.swift  # iCloud via NSFileCoordinator + NSMetadataQuery
│   └── LocalStorageManager.swift  # Local Documents dir JSON read/write
├── ViewModels/
│   └── AppViewModel.swift         # Central @MainActor state + all business logic
└── Views/
    ├── ContentView.swift          # TabView root, design tokens, toast, error banner
    ├── ServerSetupView.swift      # Server URL onboarding (SelfHive only)
    ├── BillsView.swift            # Bills tab — expandable card editor
    ├── SummaryView.swift          # Summary tab — per-person cards + breakdown
    ├── SendReceiveView.swift      # Send/Receive tab + checklist
    ├── TrendsView.swift           # Trends tab — Swift Charts, person/bill toggle
    ├── SettingsView.swift         # Settings — people, greetings, email, data
    ├── HexagonBackground.swift    # Canvas hex grid background + button styles
    └── MailComposeView.swift      # UIViewControllerRepresentable for Mail compose
```

---

## Critical Patterns

1. **Safe array mutation** — Never hold a stale binding into `vm.state.bills[]` or
   `vm.state.people[]`. Always look up the current index before mutating.

2. **All state flows through `AppViewModel`** — injected as `@EnvironmentObject`.
   Views read `@Published` properties, call view model methods to mutate.

3. **Save strategy matches web app** — `AppState` saves are debounced 600ms.
   `MonthData` saves are immediate via `saveMonthNow()`.

4. **`personId` vs `coveredById`** — same semantics as web app.
   `coveredById` redirects who actually pays. `computeBillSplit()` routes accordingly.

5. **Month snapshots** — `_myTotal` and `_owes` are cached in `MonthData` on each save.
   Trends reads these caches, not live recomputation.

6. **Preserve bills** — `autoFillPreservedBills()` copies previous month data only
   when target month has zero data. Never overwrites.

7. **Person "me" normalization** — On load, ensures first person always has `id: "me"`.

8. **Dark mode enforced** — `.preferredColorScheme(.dark)` on root. No light mode toggle.

---

## Design Tokens

Dark theme matching the web app. Defined as `Color` extensions in `ContentView.swift`:

```
bhBackground: #0c0d0f    bhSurface: #141518    bhSurface2: #1c1e22
bhSurface3: #242629      bhBorder: #2a2c31     bhBorder2: #34373d
bhText: #e4e5e8          bhMuted: #767880      bhMuted2: #4a4c52
bhAmber: #F5A800 (brand) bhBlue: #5bc4f5       bhRed: #ef5350
```

Button styles: `BHPrimaryButtonStyle` (amber), `BHSecondaryButtonStyle` (surface),
`BHDangerButtonStyle` (red). Card modifier: `.bhCard()`.

---

## Common Tasks

**Adding a field to a model:**
Add to the struct → add `CodingKeys` entry if needed → provide default in
`init(from:)` for backward compatibility → update `AppViewModel` if it affects
computation → update relevant views.

**Adding a new view:**
Create SwiftUI view → inject `@EnvironmentObject var vm: AppViewModel` →
add tab in `ContentView.swift` TabView → follow existing card/section patterns.

**Adding an API endpoint (SelfHive):**
Add method to `APIClient.swift` → call from `AppViewModel` → guard with
`isRemote` check if it's server-only functionality.
