---
name: swift-best-practices
description: Use when developing or refactoring this macOS SwiftUI menu bar app that fetches OpenRouter credits, especially for status item lifecycle, async networking, secure credential storage, and release automation.
---

# OpenRouter MenuBar Swift Best Practices

## Overview

This skill captures **project-specific best practices** for `OpenRouterCreditMenuBar`, a native macOS menu bar app using SwiftUI + AppKit bridge (`AppDelegate`) with async network polling.

Primary goals:

- Keep menu bar behavior stable (no duplicate timers or stale state)
- Keep API key handling secure
- Keep UI updates on `MainActor`
- Keep release/build workflow reproducible

## Current Architecture Snapshot

- App entry: `OpenRouterCreditMenuBarApp` with `@NSApplicationDelegateAdaptor`.
- Runtime shell: `AppDelegate` manages `NSStatusItem` + `NSPopover`.
- Domain/service: `OpenRouterCreditManager` (ObservableObject) handles settings + fetch.
- UI surfaces:
  - `MenuBarView`: quick status/actions
  - `SettingsView`: API key, enable toggle, login item, interval
- Packaging automation: `Taskfile.yml` (`build`, `package`, `github-release`).

## Mandatory Rules for This Repo

1. **Single source of truth for refresh scheduling**
   - Keep polling in one place (prefer manager-owned timer).
   - Avoid parallel timers in both `AppDelegate` and manager.

2. **Main-thread UI mutation only**
   - Mutate `@Published` values inside `await MainActor.run { ... }`.
   - Keep network and decoding off main thread.

3. **Credential storage must be secure**
   - API keys should be stored in Keychain, not plain `UserDefaults`.
   - If migrating storage, provide fallback read path and one-time migration.

4. **Network hardening over broad ATS exceptions**
   - Prefer default ATS; remove `NSAllowsArbitraryLoads` unless truly needed.
   - Keep endpoint explicit and HTTPS-only.

5. **Settings should trigger deterministic side effects**
   - Enable/disable must explicitly start/stop monitoring.
   - Refresh interval changes should reschedule exactly one timer.

6. **Behavior docs must match runtime defaults**
   - Update README whenever defaults change (refresh interval/security claims).

## Implementation Patterns

### 1) Safe async fetch pattern

- Early-return if not enabled or missing API key.
- Set loading state before request.
- Decode typed DTOs (`CreditResponse`, `CreditData`).
- Map transport errors to user-safe messages.

Checklist:

- [ ] No force unwraps
- [ ] Status code checks before decode
- [ ] `isLoading` reset on all branches

### 2) Menu bar title updates

- Only update title from a single coordinator method (e.g., `updateMenuBarTitle`).
- Display fallback text for `loading`, `error`, and `missing key` states.
- Keep formatting centralized (`String(format: ...)`) to avoid inconsistencies.

### 3) Timer lifecycle hygiene

- Invalidate previous timer before creating a new one.
- Stop timer in disable flows and app termination path.
- Avoid anonymous timers that are not retained/cancelable.

## Security Practices (High Priority)

- Store API key in Keychain service scoped to bundle id.
- Avoid printing raw API key or auth headers.
- Keep entitlements minimal (`network.client` is required; file access only if needed).
- If app is sandboxed, document why each entitlement exists.

## Testing Strategy for This Project

Current tests are mostly templates. Add focused tests first in this order:

1. **Unit tests (`OpenRouterCreditManager`)**
   - Disabled state => no fetch
   - Missing key => no fetch
   - Successful decode updates credit/usage
   - Failure sets error state and resets loading

2. **Timer behavior tests**
   - Changing interval reschedules once
   - Disabling monitoring invalidates timer

3. **UI tests (smoke)**
   - Launch app
   - Open settings
   - Toggle monitoring and ensure no crash

For testability, abstract URLSession behind protocol or injectable client.

## Release/Build Workflow Standards

Use `Taskfile.yml` tasks as the canonical path:

- `task clean`
- `task build`
- `task package`
- `task github-release`

Best practices:

- Keep version in one place (Task vars + Xcode marketing version should stay aligned).
- Avoid destructive clean commands outside release contexts.
- Ensure `gh auth status` before `github-release`.

## Code Review Checklist (Use Every PR)

- [ ] No duplicated polling mechanism
- [ ] No UI mutation off main thread
- [ ] No plaintext API key persistence
- [ ] README reflects real behavior
- [ ] New behavior has at least one regression test
- [ ] No unnecessary entitlements or ATS relaxations

## Known Gaps Observed in Current Codebase

- README claims encrypted/keychain storage, but manager currently uses `UserDefaults`.
- README states default refresh is 30s, manager default is 300s.
- Both `AppDelegate` and manager currently schedule periodic refresh behavior.

Treat these as priority alignment items during upcoming refactors.
