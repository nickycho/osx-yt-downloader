# App localization plan

- Add a persisted language preference with system detection for English, Traditional Chinese, Japanese, and Korean; unsupported system languages fall back to English.
- Add a macOS Settings screen for changing the language and localize the existing interface, preview, dependency, and service error messages.
- Bundle four `.lproj` catalogs with SwiftPM resources and include that resource bundle in the packaged `.app`.
- Build/package the macOS app and inspect the resulting bundle contents.
