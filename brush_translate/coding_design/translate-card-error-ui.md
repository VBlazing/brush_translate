Title: Translate card error UI + language mismatch recovery

Goals
- Unify all translation errors into toast-style messaging in the translated area.
- Allow language mismatch recovery by selecting a new source language and retrying.
- Keep spacing consistent with toolbar and avoid card height jumps when toast appears.
- Remove deprecated macOS 14 onChange usage and align hover feedback with toolbar timing.

Scope of changes
- Error handling now distinguishes language mismatch to surface detected language, while all errors render via toast styling.
- Failure UI includes an optional source-language picker and a retry button; picker is only shown on language mismatch.
- Retry uses the selected source language and syncs it to settings when retrying.
- Toast spacing is aligned to card edge spacing and avoids excessive height growth.

Implementation details
- brush_translate/TranslationService.swift
  - Added TranslationError.languageMismatch with localized message:
    "语言不一致，当前检测到语言为：{displayName}".
  - Language mismatch throws languageMismatch with detected display name (via detectedDisplayName).
- brush_translate/AppModel.swift
  - translateAndShow now accepts a sourceOverride for retries.
  - On languageMismatch: show picker, populate toast message, store retry override.
  - On any error: pass a failure ToastData so all errors render as toast.
  - On retry: sync override back to sourceLanguage before re-translation.
- brush_translate/TranslationOverlayController.swift
  - TranslationCardData now carries showLanguagePicker, detectedLanguageDisplayName,
    selectedSourceLanguage, onChangeSourceLanguage.
  - showFailure passes these fields for the failure view.
- brush_translate/ContentView.swift
  - TranslationCardView tracks selectedSourceLanguage locally and syncs from data.
  - Failure UI always uses ToastView (no plain red error block).
  - Language picker only appears when showLanguagePicker is true.
  - Retry button background matches card background; hover matches toolbar selection
    background with 0.12s easeInOut animation.
  - Reduced picker/button spacing in language mismatch case.
  - Toast overlay now measures actual toast height to avoid oversized card growth.
  - Replaced deprecated onChange(of:perform:) signatures with the macOS 14 API.

UI/UX notes
- Toast bottom spacing uses a larger padding to visually match the toolbar's top spacing
  (accounting for toolbar icon padding).
- Picker wrapper decoration removed to keep the language selector light and reduce friction.

Files touched
- brush_translate/TranslationService.swift
- brush_translate/AppModel.swift
- brush_translate/TranslationOverlayController.swift
- brush_translate/ContentView.swift
- brush_translate/prompt/requirement/translate-choose-language/*

Manual verification
- Trigger any translation error: message appears in toast style with retry button.
- Trigger language mismatch: toast displays detected language; picker appears.
- Change picker value then retry: translation uses new language and settings update.
- Hover retry button: background transitions to toolbar-selected color in 0.12s.
