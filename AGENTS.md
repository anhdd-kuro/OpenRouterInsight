# AGENTS.md

This guide is for autonomous coding agents working in this repository.
It captures build/test commands and coding conventions inferred from the codebase.

## Project Snapshot

- Platform: macOS menu bar app (SwiftUI + AppKit integration)
- Xcode project: `OpenRouterCreditMenuBar.xcodeproj`
- Main scheme: `OpenRouterCreditMenuBar`
- Targets:
  - `OpenRouterCreditMenuBar`
  - `OpenRouterCreditMenuBarTests` (Swift Testing)
  - `OpenRouterCreditMenuBarUITests` (XCTest UI)
- Build configs: `Debug`, `Release`
- Deployment target: macOS `15.4`

## Source Layout

- App entry + app delegate: `OpenRouterCreditMenuBar/OpenRouterCreditMenuBarApp.swift`
- Core data/network manager: `OpenRouterCreditMenuBar/OpenRouterCreditManager.swift`
- Menu bar UI: `OpenRouterCreditMenuBar/MenuBarView.swift`
- Settings UI: `OpenRouterCreditMenuBar/SettingsView.swift`
- Activity charts UI: `OpenRouterCreditMenuBar/ActivityChartsView.swift`
- Logging utility: `OpenRouterCreditMenuBar/AppLogger.swift`
- Build helper script: `scripts/build.sh`
- Tests:
  - `OpenRouterCreditMenuBarTests/OpenRouterCreditMenuBarTests.swift`
  - `OpenRouterCreditMenuBarUITests/OpenRouterCreditMenuBarUITests.swift`

## Build Commands

Run from repo root: `/Users/ainn/Documents/kuro/tools/OpenRouterCreditMenuBar`

- Debug build:
  - `xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Debug build`
- Release build:
  - `xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Release build`
- Clean + build (matches local script behavior):
  - `xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Release -derivedDataPath "./build" -destination "platform=macOS,arch=arm64" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO clean build`
- Scripted build:
  - `./scripts/build.sh`
- Scripted build + install to `/Applications`:
  - `./scripts/build.sh --install`

## Test Commands

- Run all tests (unit + UI) via scheme:
  - `xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS"`
- Run only unit tests target:
  - `xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS" -only-testing:"OpenRouterCreditMenuBarTests"`
- Run only UI tests target:
  - `xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS" -only-testing:"OpenRouterCreditMenuBarUITests"`

### Running a single test (important)

- Swift Testing test (current sample):
  - `xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS" -only-testing:"OpenRouterCreditMenuBarTests/OpenRouterCreditMenuBarTests/example()"`
- XCTest UI test example:
  - `xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS" -only-testing:"OpenRouterCreditMenuBarUITests/OpenRouterCreditMenuBarUITests/testExample"`
- XCTest launch performance test:
  - `xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS" -only-testing:"OpenRouterCreditMenuBarUITests/OpenRouterCreditMenuBarUITests/testLaunchPerformance"`

## Lint / Static Analysis / Formatting

- No dedicated SwiftLint or swift-format config is present in this repo.
- Treat Xcode static analysis as the baseline lint step:
  - `xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Debug analyze`
- Keep formatting consistent with existing files (Xcode default Swift formatting style).
- If you use local formatters, do not introduce repository-wide reformat-only diffs.

## Coding Style Guidelines

These are conventions observed in the current code and should be preserved.

### Imports

- Use one import per line.
- Keep imports minimal and file-specific (no unused imports).
- Typical frameworks in this repo: `SwiftUI`, `Foundation`, `Charts`, `AppKit`, `Combine`, `ServiceManagement`, `UserNotifications`.
- Prefer Apple framework imports only; no third-party dependency pattern is currently established.

### Formatting

- Use 4-space indentation, no tabs.
- Keep braces on the same line as declarations/control statements.
- Prefer short `guard` early exits for invalid state.
- Use trailing closures for `Task`, `Button`, `onChange`, `onReceive`, and similar SwiftUI APIs.
- Keep long expressions wrapped across lines in Xcode-style continuation indent.

### Types and Models

- Use `struct` for value models and views; use `class` when reference semantics are required (`ObservableObject`, app delegate, logger singleton).
- Prefer protocol conformances inline with type declarations (`Codable`, `Decodable`, `Identifiable`, `LocalizedError`).
- For API payload models, mirror API keys using snake_case properties when that reduces mapping noise.
- Use explicit small helper types for UI tables/charts instead of large tuple payloads.
- Avoid force unwraps; current codebase uses optional binding and defaults.

### Naming

- Types: UpperCamelCase (`OpenRouterCreditManager`, `ActivityChartsView`).
- Properties/functions/locals: lowerCamelCase (`fetchCredit`, `selectedModelFilter`).
- Enum cases: lowerCamelCase (`twoWeeks`, `threeWeeks`).
- Use descriptive boolean names (`isLoading`, `isRefreshing`, `isKeyAnomalyAlertEnabled`).
- Prefer intention-revealing helper names (`detectAndNotifyLowCreditIfNeeded`, `performLoggedRequest`).

### State Management and Concurrency

- `OpenRouterCreditManager` is the state source; UI consumes it via `@EnvironmentObject`.
- Use `@Published` for observable mutable state.
- Perform network work asynchronously with `async/await`.
- Update UI-observed state on main actor (`await MainActor.run { ... }`) when in async contexts.
- Use `Task { ... }` from UI event handlers for async operations.
- In timer-driven or hover-driven async behavior, cancel stale tasks before scheduling new ones.

### Error Handling and Resilience

- Prefer layered `do/catch` blocks so one API failure does not block unrelated data sections.
- Convert HTTP and payload failures to domain-specific errors (`OpenRouterAPIError`).
- Parse and surface API-provided error messages where possible.
- Log failures with context (`AppLogger.shared.write(...)`) rather than swallowing errors silently.
- Gracefully degrade UI state on failures (empty arrays, fallback fetches, readable status text).

### Logging

- Use `AppLogger.shared.write(event, details:)` for runtime-significant events.
- Include context in log details (status code, counts, endpoint context, etc.).
- Keep sensitive values out of logs (never log API keys or full auth headers).

### Persistence and Configuration

- Persist lightweight settings in `UserDefaults`.
- Keep UserDefaults keys stable once introduced.
- Rehydrate persisted settings during manager/view initialization (`init` / `onAppear`).
- Side effects tied to settings changes are acceptable via `didSet` when concise and explicit.

### SwiftUI / AppKit Patterns

- Keep view state local with `@State` unless shared app-wide.
- Factor repeated UI parts into private computed views/helper functions.
- Use simple, composable view models/data transformers inside the view when no cross-file reuse exists.
- For menu bar behavior, keep AppKit lifecycle/event monitoring in `AppDelegate`.

## Test Conventions

- Unit tests currently use Swift Testing (`import Testing`, `@Test`, `#expect`).
- UI tests use XCTest (`XCTestCase`, `XCUIApplication`).
- For new logic-heavy code, prefer adding unit tests near manager/model behavior.
- For menu bar interaction or launch flow, use UI tests when unit isolation is insufficient.

## Agent Workflow Expectations

- Make focused, minimal diffs aligned with existing architecture.
- Do not rename persisted keys, notifications, or API model fields without migration reasoning.
- Do not add new dependencies or tooling configs unless requested.
- Before finishing substantial changes, run at least build + relevant tests.
- If you cannot run tests locally, state that clearly and provide exact commands.

## Cursor and Copilot Rules

- Checked `.cursor/rules/`: not present.
- Checked `.cursorrules`: not present.
- Checked `.github/copilot-instructions.md`: not present.
- Therefore, no additional Cursor/Copilot repository rules are currently defined.
