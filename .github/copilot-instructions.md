# OpenRouterCreditMenuBar - GitHub Copilot Instructions

Trust this file first. Search only when details here are missing or clearly out of date.

## Repository Overview

- Native macOS menu bar app that monitors OpenRouter credit balance and usage.
- Stack: Swift, SwiftUI + AppKit lifecycle integration, Apple Charts, Swift Concurrency.
- Project file: `OpenRouterCreditMenuBar.xcodeproj`.
- Main scheme: `OpenRouterCreditMenuBar`.
- Targets:
  - `OpenRouterCreditMenuBar` (app)
  - `OpenRouterCreditMenuBarTests` (Swift Testing)
  - `OpenRouterCreditMenuBarUITests` (XCTest)
- Deployment target: macOS `15.4`.

## Key Paths

- `OpenRouterCreditMenuBar/OpenRouterCreditMenuBarApp.swift`: app entry + `AppDelegate` menu bar lifecycle.
- `OpenRouterCreditMenuBar/OpenRouterCreditManager.swift`: shared state (`ObservableObject`), API calls, caching, timer refresh, notifications.
- `OpenRouterCreditMenuBar/MenuBarView.swift`: main menu bar popover UI.
- `OpenRouterCreditMenuBar/SettingsView.swift`: API key and app settings.
- `OpenRouterCreditMenuBar/ActivityChartsView.swift`: chart-based usage/activity sections.
- `OpenRouterCreditMenuBar/AppLogger.swift`: runtime logging.
- `scripts/build.sh`: clean unsigned release build; optional install to `/Applications`.

## Build and Run Commands

Run all commands from repo root.

1) Debug build (fast validation):

```bash
xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Debug build
```

2) Release build:

```bash
xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Release build
```

3) Scripted clean unsigned release build:

```bash
./scripts/build.sh
```

4) Scripted build and install to `/Applications`:

```bash
./scripts/build.sh --install
```

Important pre/post conditions:

- `scripts/build.sh` always performs `clean build` with derived data in `./build`.
- `scripts/build.sh --install` removes existing `/Applications/Open-router Insight.app` before copying new app.
- Unsigned local release build is expected (`CODE_SIGNING_ALLOWED=NO`).

## Test and Validation Commands

Run these before finalizing non-trivial changes.

1) All tests:

```bash
xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS"
```

2) Unit tests only:

```bash
xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS" -only-testing:"OpenRouterCreditMenuBarTests"
```

3) UI tests only:

```bash
xcodebuild test -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -destination "platform=macOS" -only-testing:"OpenRouterCreditMenuBarUITests"
```

4) Static analysis baseline:

```bash
xcodebuild -project "OpenRouterCreditMenuBar.xcodeproj" -scheme "OpenRouterCreditMenuBar" -configuration Debug analyze
```

## Coding Conventions

- Follow Xcode default Swift formatting with 4-space indentation.
- Use `guard` for early exits and safe optional handling; avoid force unwraps.
- Keep one import per line and avoid unused imports.
- Preserve architecture: `OpenRouterCreditManager` is the shared source of truth for view state.
- Keep `@Published` state mutations on main actor from async code (`await MainActor.run { ... }`).
- Use `AppLogger.shared.write(...)` for meaningful runtime events.
- Do not log secrets (API key, bearer token, auth headers).

## Change Boundaries

- Keep diffs focused and minimal; avoid broad refactors unless requested.
- Preserve existing `UserDefaults` keys and API payload fields unless migration is explicitly requested.
- Ask before changing notification identifiers, API contract behavior, install path, or signing/packaging flow.
- Do not add new dependencies or repository-wide tooling changes unless requested.

## Validation Workflow for Agents

- Always run at least one successful build command after code edits.
- Run the most relevant test scope for the touched area (unit and/or UI).
- If you cannot run a validation step, clearly state what was not run and provide exact command(s).
