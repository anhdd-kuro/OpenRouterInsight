# OpenRouterCreditMenuBar - Agent Context

## Commands

Run from repo root: `/Users/ainn/Documents/kuro/tools/OpenRouterCreditMenuBar`

- Build debug:
  - `xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Debug build`
- Build release:
  - `xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Release build`
- Build release (clean, unsigned, local derived data):
  - `xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Release -derivedDataPath "./build" -destination "platform=macOS,arch=arm64" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO clean build`
- Scripted build:
  - `./scripts/build.sh`
- Scripted build + install to `/Applications`:
  - `./scripts/build.sh --install`
- Run all tests:
  - `xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS"`
- Run unit tests only:
  - `xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS" -only-testing:"OpenRouterCreditMenuBarTests"`
- Run UI tests only:
  - `xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS" -only-testing:"OpenRouterCreditMenuBarUITests"`
- Static analysis baseline:
  - `xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Debug analyze`

## Project Structure

- `OpenRouterCreditMenuBar.xcodeproj/` - Xcode project and target configuration
- `OpenRouterCreditMenuBar/OpenRouterCreditMenuBarApp.swift` - app entry and AppKit lifecycle
- `OpenRouterCreditMenuBar/OpenRouterCreditManager.swift` - API fetches, state, caching, notifications
- `OpenRouterCreditMenuBar/MenuBarView.swift` - menu bar popover UI
- `OpenRouterCreditMenuBar/SettingsView.swift` - settings and API key configuration
- `OpenRouterCreditMenuBar/ActivityChartsView.swift` - charts and activity visuals
- `OpenRouterCreditMenuBar/AppLogger.swift` - runtime logging utility
- `OpenRouterCreditMenuBarTests/` - Swift Testing unit tests (`@Test`, `#expect`)
- `OpenRouterCreditMenuBarUITests/` - XCTest UI tests
- `scripts/build.sh` - local clean release build and optional install

## Tech Stack

- Swift (Xcode 16+ toolchain)
- SwiftUI + AppKit integration (menu bar app)
- Apple Charts framework
- Swift Concurrency (`async`/`await`)
- Swift Testing for unit tests + XCTest for UI tests
- macOS deployment target: `15.4`

## Code Style

- Use 4-space indentation and Xcode default formatting
- Prefer `guard` early exits for invalid state
- Keep one import per line, avoid unused imports
- Prefer descriptive lowerCamelCase members and UpperCamelCase types

```swift
// do
Task {
    await creditManager.fetchCredit(showLoadingText: false)
}

// do not
Task { await creditManager.fetchCredit(showLoadingText:false) }
```

```swift
// do
guard !apiKey.isEmpty && isEnabled else { return }

// do not
if apiKey.isEmpty || !isEnabled {
    return
}
```

## Workflow

- Keep diffs focused; avoid broad refactors unless requested
- Preserve `UserDefaults` keys and API payload fields unless migration is explicitly part of the task
- Run at least one build plus relevant tests before finalizing substantial changes
- Do not add dependencies or tooling configs unless requested

## Boundaries

### Always

- Use `OpenRouterCreditManager` as the shared state source for views
- Keep UI updates on main actor when mutating published state from async work
- Log meaningful runtime events using `AppLogger.shared.write(...)`

### Ask first

- Changes affecting persistence keys, notification identifiers, or API contracts
- Changes that alter install path, signing behavior, or packaging flow

### Never

- Never commit secrets (API keys, tokens, credentials)
- Never log full authorization headers or raw API keys
- Never force-unwrap values when safe optional handling is practical
- Never introduce repository-wide formatting-only diffs

## Known Gotchas

- `scripts/build.sh` builds unsigned release output into `./build` and can remove/replace app in `/Applications` when `--install` is used
- Menu bar lifecycle behavior is managed in `AppDelegate`; avoid moving it into pure SwiftUI scene flow
- Unit tests use Swift Testing syntax, while UI tests use XCTest syntax
