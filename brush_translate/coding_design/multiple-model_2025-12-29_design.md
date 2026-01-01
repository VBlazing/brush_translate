# Multiple Model Translation - Implementation Plan

## Scope
- Add a "Models" section in Settings to manage multiple providers.
- Support DeepSeek, Doubao, Gemini with fixed model lists.
- Switch translation provider at runtime based on selected provider.
- Add provider-specific API key storage and validation.
- Keep validation result ephemeral (reset on Settings close).

## UI/UX: Settings "Models" Section
### Structure
- Location: Settings page between "Translation" and "Features" sections.
- Layout: a list of provider rows, each row supports expand/collapse.

### Provider List Item (collapsed)
- Left to right:
  - Expand/Collapse icon (chevron).
  - Provider icon (SF Symbol for now).
  - Provider name.
  - Status: show "Selected" text if provider is currently applied.
  - Right side action: show "Apply" button when hovered OR expanded.

### Hover/Expanded Behavior
- Use hover tracking to show the "Apply" button only on hover or when expanded.
- Expand state is per provider; multiple providers can be expanded.

### Apply Button
- Style: primary button consistent with theme.
- Disabled when API key is empty; show "Missing API Key" text on left of the button.
- Clicking Apply:
  - Normalize model selection (fallback to default if user input invalid).
  - Set global selected provider (single-select).

### Expanded Content (three rows)
1) Model Selection
- UI: searchable combobox (NSComboBox wrapped in SwiftUI).
- Options: provider-specific model list.
- Default: first model in list.
- On submit: normalize selection to known list.

2) API Key
- UI: SecureField with reveal toggle (eye icon).
- Behavior: same as existing DeepSeek API key control.
- Stored per provider.

3) Verify
- UI: secondary button with loading state.
- On click:
  - Trigger provider validation call (see Validation section).
  - Show loading indicator while in progress.
  - After completion: show result text + success/failure icon on the left of the button.
  - Do not persist result; reset when Settings is closed.

## Data Model & Persistence
### New Types
- TranslationProvider enum:
  - deepseek / doubao / gemini
  - displayName, iconName, models, defaultModel.

### AppModel State
- selectedProvider: TranslationProvider
- API keys:
  - deepseekAPIKey
  - doubaoAPIKey
  - geminiAPIKey
- model selection per provider:
  - deepseekModel
  - doubaoModel
  - geminiModel

### UserDefaults Keys
- brush_translate.provider
- brush_translate.deepseek.apiKey
- brush_translate.doubao.apiKey
- brush_translate.gemini.apiKey
- brush_translate.deepseek.model
- brush_translate.doubao.model
- brush_translate.gemini.model

### Validation State (Settings only)
- verifyingProviders: Set<TranslationProvider>
- verificationResults: [TranslationProvider: result]
- These live in ContentView state and are not persisted.

## Translation Routing
### TranslationService API
- translate(...) now includes provider + model + apiKey.
- dispatch based on provider:
  - DeepSeek: OpenAI-compatible endpoint.
  - Doubao: OpenAI-compatible endpoint.
  - Gemini: Google Generative Language endpoint.

### Provider Endpoints
- DeepSeek:
  - https://api.deepseek.com/v1/chat/completions
  - Header: Authorization: Bearer <API_KEY>
  - Response: OpenAI-like JSON

- Doubao (Volcengine Ark):
  - https://ark.cn-beijing.volces.com/api/v3/chat/completions
  - Header: Authorization: Bearer <API_KEY>
  - Response: OpenAI-like JSON

- Gemini:
  - https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={API_KEY}
  - Body uses system_instruction + contents + generation_config
  - Response: candidates[0].content.parts[0].text

### Structured Output
- Use the same JSON schema (state/error_message/translate_result).
- For all providers:
  - System prompt enforces JSON output.
  - Response is decoded and then cached.

### Caching
- Cache key must include provider + model + source + target + text.

### Analyze (DeepSeek only)
- Analyze remains DeepSeek-only.
- The Analyze button is shown only when selected provider is DeepSeek.

## Validation
### API Behavior
- Reuse translate() with a short test input ("Hello") to validate connectivity.
- If missing API key: throw TranslationError.missingAPIKey(provider).

### UI Behavior
- During validation: show loading indicator.
- On completion: show success/failure message next to button.
- Reset validation results on Settings close (by virtue of view state).

## Error Handling
- missingAPIKey now includes provider and is shown as: "Missing <Provider> API Key".
- Network errors bubble up as-is.
- Invalid response errors show a generic failure message.

## Files to Change
- Add: brush_translate/TranslationProvider.swift
- Update: brush_translate/ContentView.swift
  - new Models section
  - provider list UI
  - ModelComboBox wrapper
  - validation UI state
- Update: brush_translate/AppModel.swift
  - new provider + API key + model storage
  - translate routing
  - validation helper
- Update: brush_translate/TranslationService.swift
  - new provider routing
  - OpenAI-compatible + Gemini request/response
  - cache key update
- Update: brush_translate/TranslationOverlayController.swift
  - showAnalyzeButton configurable

## UI Tokens / Theme Consistency
- Primary button: .borderedProminent + theme tint
- Secondary button: .bordered + theme tint
- Text colors use theme.sourceText / theme.translateText / theme.errorText
- Input fields reuse .formFieldBackground(theme)

## Acceptance Checklist
- Models section renders a list for DeepSeek / Doubao / Gemini.
- Each provider expands to show Model / API Key / Verify.
- Apply button is visible only on hover or expanded, and disabled with empty API key.
- Switching provider affects translation call.
- Validation shows loading + success/failure and resets on Settings close.
- Analyze button shows only when DeepSeek is active.
