# Repository Guidelines

## Project Structure & Module Organization
- App source lives in `brush_translate/` (Swift, AppKit). Key files: `SelectionCapture.swift` (text capture), `TranslationOverlayController.swift` (UI overlay), `TranslationService.swift` (network/service logic), `HotKeyManager.swift` (global shortcuts), and `ContentView.swift`/`brush_translateApp.swift` (entry/SwiftUI wiring). Assets reside in `Assets.xcassets`. The Xcode project is `brush_translate.xcodeproj/`. Builds output to `build/`.

## Build, Test, and Development Commands
- `open brush_translate.xcodeproj` — open in Xcode for interactive development and run/debug.
- `xcodebuild -project brush_translate.xcodeproj -scheme brush_translate -configuration Debug -destination 'platform=macOS'` — CLI build for macOS.
- Tests are currently absent; add a scheme target if you introduce them. Prefer `xcodebuild ... test` once tests exist.

## Coding Style & Naming Conventions
- Swift 5+, 4-space indentation, camelCase for functions/vars, PascalCase for types. Keep enums `lowerCamelCase` for cases unless mirroring system values.
- Favor small, focused types; keep platform APIs (AX, CGEvent) wrapped in helper functions as done in `SelectionCapture`.
- Trim whitespace from user-facing strings before use; restore user state (e.g., pasteboard) when mutating global resources.

## Testing Guidelines
- No unit/UI test targets yet. When adding: place under `brush_translateTests/` or `brush_translateUITests/` and wire to the scheme.
- Name tests with intent, e.g., `testCopyRestoresPasteboard()`.
- For clipboard/hotkey logic, prefer protocol abstractions so side effects can be mocked; avoid flakiness from real pasteboard or accessibility calls.

## Commit & Pull Request Guidelines
- Commits should be concise and present-tense, describing behavior change (e.g., "Handle empty pasteboard selection").
- For PRs: include summary, before/after behavior, any UX/UI screenshots, and validation notes (manual steps or commands run). Link issues/tasks when applicable.

## Security & Configuration Tips
- Accessibility APIs require user consent; ensure instructions surface permission prompts. Avoid logging sensitive text captured from the clipboard/selection.
- Keep network calls (if added to translation service) behind HTTPS and handle failures gracefully to avoid blocking hotkeys/UI.
