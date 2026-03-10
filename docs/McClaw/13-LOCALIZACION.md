# 13 - Multi-language Localization

## Status: Infrastructure completed

## Strategy

Native Apple system with `.lproj/Localizable.strings` via SPM.

### Implemented

- `Package.swift`: `defaultLocalization: "en"`
- `Resources/en.lproj/Localizable.strings`: 566 strings extracted from the entire app
- `build-app.sh`: automatic copy of `.lproj` to the app bundle (step 4d)
- Programmatic strings (NSMenuItem, NSAlert, PermissionManager, ConnectorModels, NodeMode) use `String(localized:bundle: .module)`
- SwiftUI views (`Text()`, `Button()`, `Label()`, etc.) use `LocalizedStringKey` automatically
- CronJobEditor was already using `String(localized:)` — works via the build script
- Fixed hardcoded Spanish strings ("Copiar" -> "Copy", "Escribe / para comandos" -> "Type / for commands")

### How It Works

1. SwiftUI views: `Text("literal")` creates a `LocalizedStringKey` that looks up in `Bundle.main`. In the `.app`, the build script copies the `.lproj` folders to `Contents/Resources/`, so `Bundle.main` finds them
2. Programmatic strings: use `String(localized: "key", bundle: .module)` to access the SPM resource bundle directly
3. During development (`swift run`): the keys are displayed directly (they are the English text), so it works without issue

### How to Add a Language

1. Create `McClaw/Sources/McClaw/Resources/XX.lproj/Localizable.strings` (copy `en.lproj` as a base)
2. Translate all values (keys remain in English)
3. Rebuild with `./scripts/build-app.sh`
4. The build script automatically copies all `.lproj` folders to the bundle

---

## Languages

### Tier 1 — Required for Launch
| Language | Code |
|----------|------|
| English | `en` |
| Spanish | `es` |
| French | `fr` |
| German | `de` |
| Italian | `it` |
| Portuguese | `pt` |
| Catalan | `ca` |
| Galician | `gl` |
| Basque | `eu` |
| Dutch | `nl` |
| Polish | `pl` |
| Romanian | `ro` |
| Czech | `cs` |
| Hungarian | `hu` |
| Swedish | `sv` |
| Danish | `da` |
| Norwegian | `nb` |
| Finnish | `fi` |
| Greek | `el` |
| Bulgarian | `bg` |
| Croatian | `hr` |
| Slovak | `sk` |
| Slovenian | `sl` |
| Estonian | `et` |
| Latvian | `lv` |
| Lithuanian | `lt` |
| Irish | `ga` |
| Maltese | `mt` |
| Ukrainian | `uk` |

### Tier 2 — Maximum Global Coverage
| Language | Code |
|----------|------|
| Simplified Chinese | `zh-Hans` |
| Traditional Chinese | `zh-Hant` |
| Japanese | `ja` |
| Korean | `ko` |
| Arabic | `ar` |
| Hebrew | `he` |
| Hindi | `hi` |
| Bengali | `bn` |
| Thai | `th` |
| Vietnamese | `vi` |
| Indonesian | `id` |
| Malay | `ms` |
| Turkish | `tr` |
| Russian | `ru` |
| Persian | `fa` |
| Swahili | `sw` |

### Tier 3 — Future Expansion
| Language | Code |
|----------|------|
| Portuguese (Brazil) | `pt-BR` |
| Spanish (Latin America) | `es-419` |
| French (Canada) | `fr-CA` |
| Tamil | `ta` |
| Telugu | `te` |
| Urdu | `ur` |
| Filipino | `fil` |
| Amharic | `am` |

---

## Technical Notes

- All UI-visible strings must use `String(localized:)` or `LocalizedStringKey`
- RTL (right-to-left) support needed for: Arabic, Hebrew, Persian, Urdu
- Pluralization with `.stringsdict` or String Catalogs for languages with complex rules (Polish, Arabic, Russian)
- Date/time/number formats via `Foundation.Locale` (already automatic in SwiftUI)
- Verify that layout does not break with long languages (German) or compact ones (Chinese, Japanese)
