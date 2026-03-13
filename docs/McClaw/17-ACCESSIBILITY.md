# McClaw - Accessibility Guide

> **Doc 17** — VoiceOver, Dynamic Type, Reduce Motion, Alto Contraste, Focus Management

---

## 1. Estado Actual (Auditoría)

| Métrica | Valor |
|---------|-------|
| Archivos de vistas | 67 |
| `.accessibilityLabel` usados | 3 (solo en SettingsWindow.swift) |
| `@ScaledMetric` | 0 |
| `AccessibilityReduceMotion` | 0 |
| `AccessibilityContrast` | 0 |
| `@AccessibilityFocusState` | 0 |
| `.accessibilityIdentifier` | 0 |
| Tests de accesibilidad | 0 |

### Lo que SwiftUI da "gratis"

Los controles estándar (`Button`, `TextField`, `Toggle`, `Picker`, `Slider`) ya se anuncian en VoiceOver con su label de texto. El problema son:

- **Botones icon-only** (`Image(systemName:)` sin texto) → VoiceOver dice el nombre del SF Symbol, que suele ser críptico
- **Elementos custom** (Circle con iniciales, gradientes, waveforms) → Completamente invisibles
- **Contenido hover-to-reveal** → VoiceOver no puede descubrirlo
- **Tamaños hardcoded** → No respetan Dynamic Type
- **Animaciones** → No respetan Reduce Motion

---

## 2. Infraestructura Compartida (Phase 0)

Antes de tocar cualquier vista, crear la infraestructura reutilizable.

### 2.1 Archivo: `Views/Shared/AccessibilityModifiers.swift`

```swift
import SwiftUI

// MARK: - Reduce Motion

/// Wraps animation respetando la preferencia del usuario.
/// Uso: .motionSafe { withAnimation(.easeInOut) { ... } }
struct ReduceMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // Las vistas individuales usan motionSafeAnimation() en sus withAnimation
    }
}

extension View {
    /// Ejecuta animación solo si Reduce Motion está desactivado.
    func motionSafeAnimation<V: Equatable>(
        _ animation: Animation? = .default,
        value: V
    ) -> some View {
        modifier(MotionSafeAnimationModifier(animation: animation, value: value))
    }
}

private struct MotionSafeAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Icon Button Label

extension View {
    /// Añade accessibilityLabel a un botón icon-only.
    /// Mantiene el .help() existente intacto.
    func iconButtonLabel(_ key: LocalizedStringKey) -> some View {
        self.accessibilityLabel(Text(key))
    }
}

// MARK: - Hover Reveal (VoiceOver siempre visible)

struct HoverRevealModifier: ViewModifier {
    @Environment(\.accessibilityEnabled) private var a11yEnabled
    let isHovering: Bool

    func body(content: Content) -> some View {
        content.opacity(a11yEnabled ? 1.0 : (isHovering ? 1.0 : 0.0))
    }
}

extension View {
    /// Hace visible contenido hover-to-reveal cuando VoiceOver está activo.
    func hoverReveal(isHovering: Bool) -> some View {
        modifier(HoverRevealModifier(isHovering: isHovering))
    }
}

// MARK: - Accessibility Announcement

extension View {
    /// Anuncia cambios de valor a VoiceOver.
    func accessibilityAnnounce<V: Equatable>(
        for value: V,
        message: @escaping (V) -> String
    ) -> some View {
        self.onChange(of: value) { _, newValue in
            AccessibilityNotification.Announcement(message(newValue)).post()
        }
    }
}
```

### 2.2 Convención `@ScaledMetric`

No se puede usar `@ScaledMetric` como `static` — cada vista declara sus propias propiedades:

```swift
// Dentro de cada View que use dimensiones fijas:
@ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36
@ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 28
@ScaledMetric(relativeTo: .caption) private var badgeHeight: CGFloat = 20
```

**Valores estándar de McClaw** (usar estos defaults en toda la app):

| Elemento | Default | relativeTo |
|----------|---------|------------|
| Avatar | 36 | .body |
| Icon button | 28 | .body |
| Badge | 20 | .caption |
| Sidebar width | 260 | .body |
| Code font | 13 | .body |
| Action bar icon | 12 | .caption |

### 2.3 Colores Semánticos en Theme.swift

Reemplazar colores literales por semánticos con soporte de alto contraste:

```swift
// En Theme.swift, añadir:
extension Theme {
    // Reemplaza .green, .blue, .orange literales
    static func statusColor(
        _ status: some StatusRepresentable,
        contrast: AccessibilityContrast = .standard
    ) -> Color {
        // Colores con suficiente contraste WCAG AA (4.5:1 texto, 3:1 componentes)
    }
}
```

**Colores a reemplazar**:

| Uso actual | Archivos | Reemplazo |
|------------|----------|-----------|
| `.green` (conectado/OK) | VoiceOverlayView, ChatWindow, MessageBubbleView | `Theme.statusConnected` |
| `.orange` (warning) | VoiceOverlayView, GitActionConfirmation | `Theme.statusWarning` |
| `.red` (error/stop) | ChatInputBar, MessageBubbleView | `Theme.statusError` |
| `.blue` (info) | VoiceOverlayView | `Theme.statusInfo` |
| `.gray` (desconectado) | ChatWindow | `Theme.statusDisconnected` |

### 2.4 Syntax Highlighting Dual Theme

`MarkdownContentView.swift` tiene 8 `NSColor` RGB hardcoded (líneas 311-318). Necesitan:

1. Variante light mode (actualmente solo sirven para dark)
2. Mayor contraste en modo alto contraste
3. Detección via `NSApp.effectiveAppearance.bestMatch(from:)`

### 2.5 Localización

Todas las accessibility labels usan `String(localized:, bundle: .module)`. Prefijo sugerido para keys de accesibilidad: `a11y_*`.

```
// En Localizable.strings:
"a11y_send_message" = "Send message";
"a11y_attach_files" = "Attach files";
"a11y_voice_mode_off" = "Voice mode, off";
"a11y_voice_mode_listening" = "Voice mode, listening";
```

---

## 3. Chat Core (Phase 1) — Máximo Impacto

El chat es el 90%+ del tiempo de uso. Un usuario de VoiceOver no puede usar la app sin esto.

### 3.1 ChatInputBar.swift

| Elemento | Problema | Solución |
|----------|----------|----------|
| Botón Attach | `.help()` sin label | Añadir `.iconButtonLabel("a11y_attach_files")` |
| Botón Voice | `.help()` sin label | `.iconButtonLabel()` con estado (off/listening) |
| Botón Image Gen | `.help()` sin label | `.iconButtonLabel()` con estado (on/off) |
| Botón Install | `.help()` sin label | `.iconButtonLabel()` |
| Botón Plan Mode | `.help()` sin label | `.iconButtonLabel()` con estado |
| Botón Send/Abort | Icon-only | `.iconButtonLabel()` condicional |
| Model Picker | Sin label claro | `.accessibilityLabel()` con nombre del modelo actual |
| NSTextView (MultiLineTextInput) | Sin accesibilidad AppKit | `setAccessibilityLabel()`, `setAccessibilityRole(.textArea)`, `setAccessibilityHelp("Enter to send, Shift+Enter for new line")` en `makeNSView` |

**Nota**: El `SubmitTextView` (NSTextView subclass) necesita accesibilidad AppKit, no SwiftUI:

```swift
// En makeNSView o updateNSView:
textView.setAccessibilityLabel(
    String(localized: "a11y_chat_input", bundle: .module)
)
textView.setAccessibilityRole(.textArea)
textView.setAccessibilityHelp(
    String(localized: "a11y_chat_input_help", bundle: .module)
)
```

### 3.2 MessageBubbleView.swift

| Elemento | Problema | Solución |
|----------|----------|----------|
| Avatar usuario (Circle + iniciales) | Invisible a VoiceOver | `.accessibilityLabel("a11y_user_avatar")` |
| Avatar asistente | Invisible | `.accessibilityLabel("McClaw")` |
| Action bar (copy, etc.) | Solo visible en hover | Aplicar `.hoverReveal(isHovering:)` |
| ActionBarButton | Usa `.help()` sin label | `.iconButtonLabel(tooltip)` |
| ToolCallCard | Elementos sueltos | `.accessibilityElement(children: .combine)` con label "Tool: name, status" |
| GeneratedImageCard | Botón save en hover | `.hoverReveal()` + `.accessibilityLabel()` en la imagen |

### 3.3 ChatWindow.swift

| Elemento | Problema | Solución |
|----------|----------|----------|
| Sidebar toggle | Solo `.help()` | `.iconButtonLabel()` con estado (abierto/cerrado) |
| Gateway status Circle | Decorativo sin label | `.accessibilityLabel("Gateway connected/disconnected")` |
| CLI selector pills | Sin `.isSelected` | `.accessibilityAddTraits(.isSelected)` al activo, `.accessibilityLabel(provider.name)` |
| Streaming state | Sin anuncios | `.accessibilityAnnounce(for: isStreaming)` → "McClaw is responding" / "Response complete" |

### 3.4 ChatSidebar.swift

| Elemento | Problema | Solución |
|----------|----------|----------|
| SidebarNavItem | Icon + label sin badge context | `.accessibilityLabel(label + badge count)`, `.accessibilityAddTraits(.isSelected)` |
| SidebarSessionRow | Sin selección | `.accessibilityAddTraits(.isSelected)` cuando seleccionado |
| User avatar footer | Circle invisible | `.accessibilityLabel("a11y_user_avatar")` |

### 3.5 ThinkingWordsView.swift

```swift
// El typewriter animado es confuso para VoiceOver.
// Reemplazar con un label estable:
.accessibilityElement(children: .ignore)
.accessibilityLabel(String(localized: "a11y_thinking", bundle: .module))
```

Con Reduce Motion: mostrar texto estático "McClaw is thinking..." en vez del efecto typewriter.

### 3.6 SlashCommandPopup.swift

- Container: `.accessibilityElement(children: .contain)`
- Cada fila: `.accessibilityLabel(command.name + " — " + command.description)`
- Fila seleccionada: `.accessibilityAddTraits(.isSelected)`
- Al cambiar selección: announcement del nuevo comando

### 3.7 WelcomeView.swift

- Logo: `.accessibilityLabel("McClaw")`
- QuickActionChip: `.accessibilityLabel(label)` + `.accessibilityAddTraits(.isButton)`
- Botón cerrar panel: `.iconButtonLabel("a11y_close")`

### 3.8 ShimmerImagePlaceholder.swift

```swift
.accessibilityElement(children: .combine)
.accessibilityLabel(String(localized: "a11y_generating_image", bundle: .module))
// Con Reduce Motion: gradiente estático en vez de shimmer animado
```

---

## 4. Settings y Configuración (Phase 2)

### 4.1 Patrón General para Settings

Cada vista de settings usa `Form` con `.formStyle(.grouped)`. SwiftUI asocia labels de `TextField`/`Toggle`/`Picker` automáticamente. Lo que falta:

1. **Status indicators** (círculos de color) → Añadir `.accessibilityLabel()` con el estado
2. **Botones OAuth** ("Connect") → Incluir nombre del conector en el label
3. **Tabs de navegación** → Si son icon-only, añadir `.iconButtonLabel()`

### 4.2 Archivos Específicos

| Archivo | Cambios clave |
|---------|---------------|
| SettingsWindow.swift | Extender los 3 labels existentes a: sidebar items, slider values, todos los previews |
| ConnectorDetailView.swift | Status circles, OAuth buttons con nombre, token status |
| ConnectorsSettingsTab.swift | Cards con `.accessibilityElement(children: .combine)` + estado conexión |
| CronJobEditor.swift | Form fields association, time pickers |
| MCPSettingsTab.swift | Server status labels, add/remove buttons |
| MCPServerEditor.swift | Form fields, env var entries |
| NativeChannelsSettingsTab.swift | Channel cards con status, start/stop buttons |
| VoiceSettings.swift | Toggle states, slider values |
| RemoteSettingsTab.swift | Connection status, test button |
| BitNetSettingsTab.swift | Model status, download progress |
| SkillsSettings.swift | Skill cards, enable/disable |
| ChannelConfigForm.swift (ConfigSchemaForm) | Dynamic form — labels ya vienen del schema, verificar |

---

## 5. Vistas Especializadas (Phase 3)

### 5.1 Git Views (13 archivos en Views/Git/)

**Patrón común**: List rows con múltiples datos → usar `.accessibilityElement(children: .combine)`:

| Vista | Label combinado |
|-------|----------------|
| GitRepoRow | "repo-name, 42 stars, Swift, 3 open PRs" |
| GitBranchListView rows | "branch-name, default, 2 ahead 1 behind" |
| GitPRListView rows | "PR title, open, by author, 3 reviews" |
| GitIssueListView rows | "Issue title, open, 2 labels, assigned to X" |
| GitCommitListView rows | "commit message, author, 2 hours ago" |

**Específicos**:

- **GitPanelView**: Chat collapse toggle → `.iconButtonLabel()`, platform selector → `.isSelected` trait
- **GitFileTreeView**: Directories → `.accessibilityAddTraits(.isButton)` + expand/collapse hint
- **GitContextChip**: `.accessibilityLabel("Git context: repo/branch")` + dismiss button label
- **GitActionConfirmationCard**: `.accessibilityAddTraits(.isModal)`, confirm/cancel labels claros
- **GitPlatformSelector**: Pills con `.isSelected` (mismo patrón que CLI selector)
- **GitEmptyStateView**: Straightforward, el `ContentUnavailableView` ya es accesible

### 5.2 Canvas

- **CanvasView.swift**: WKWebView tiene su propio modelo de accesibilidad. El container SwiftUI necesita `.accessibilityLabel("Canvas")`. El contenido web debe gestionarse desde el HTML/JS inyectado.

### 5.3 Voice

- **VoiceOverlayView.swift**:
  - Waveform Circle → `.accessibilityHidden(true)` (es decorativo)
  - State label ("Listening", "Speaking") → ya es texto, pero añadir announcement en cambios de estado
  - Control buttons → `.iconButtonLabel()` con estado

### 5.4 Security

- **ExecApprovalDialog.swift**: Dialog crítico de seguridad
  - `.accessibilityAddTraits(.isModal)`
  - Botones con roles claros: "Allow Once", "Allow Always", "Deny"
  - Focus por defecto en "Allow Once" (seguridad)
  - Comando a aprobar: `.accessibilityLabel("Command to approve: ...")`

### 5.5 Onboarding

- **OnboardingWizard.swift**:
  - Page indicators (dots) → `.accessibilityLabel("Page X of Y")`
  - Navigation buttons → label con dirección
  - Fixed frame 520x440 → considerar `@ScaledMetric` para altura mínima

### 5.6 Menu Bar

- **MenuBarLabel.swift**: Icon-only → `.accessibilityLabel()` con estado actual (idle/working/paused)
- **MenuContentView.swift**: Auditar botones icon-only
- **FloatingChatPanel.swift**: NSPanel → `setAccessibilityLabel()` en el panel, `setAccessibilityRole(.popover)`

### 5.7 Install Views

- **InstallProgressView.swift**: Progress → announcement en cada milestone
- **InstallPlanReviewSheet.swift**: Pasos de review → labels claros
- **InstallationsContentView.swift**: Status indicators

---

## 6. Motion, Contraste y Focus (Phase 4)

### 6.1 Reduce Motion

Aplicar `.motionSafeAnimation()` o check manual en todos los sitios con animación:

| Archivo | Animación | Comportamiento con Reduce Motion |
|---------|-----------|----------------------------------|
| ShimmerImagePlaceholder | Shimmer continuo | Placeholder estático (frosted glass) |
| ThinkingWordsView | Typewriter letra a letra | Texto estático completo |
| MessageBubbleView | Hover fade in/out | Siempre visible |
| GeneratedImageCard | Scale on hover | Sin escala |
| ChatSidebar | User menu slide | Aparición instantánea |
| WelcomeView | Quick action panel expand | Aparición instantánea |
| ChatWindow | Sidebar slide, scroll-to-bottom | Transición instantánea |
| VoiceOverlayView | Waveform pulse | Icono estático |
| SlashCommandPopup | List selection highlight | Sin animación |
| MenuBarLabel | Icon animation states | Icono estático (estado actual) |

**Patrón de implementación**:

```swift
// Antes:
withAnimation(.easeInOut(duration: 0.2)) {
    showSidebar.toggle()
}

// Después:
if reduceMotion {
    showSidebar.toggle()
} else {
    withAnimation(.easeInOut(duration: 0.2)) {
        showSidebar.toggle()
    }
}

// O con el modifier en la vista:
.motionSafeAnimation(.easeInOut(duration: 0.2), value: showSidebar)
```

### 6.2 Alto Contraste

En `Theme.swift`, leer `@Environment(\.accessibilityContrast)` y ajustar:

- Bordes: `.opacity(0.12)` → `.opacity(0.4)` en alto contraste
- Backgrounds sutiles: `.quaternary.opacity(0.5)` → `.quaternary` (sin opacity)
- Separadores: hacer más visibles
- Focus rings: más gruesos y contrastados

### 6.3 Focus Management

```swift
// En ChatWindow:
@FocusState private var focusedArea: ChatFocus?

enum ChatFocus: Hashable {
    case sidebar
    case messageList
    case inputBar
}

// Al crear nuevo chat: focusedArea = .inputBar
// Al completar streaming: mantener focus estable (no mover)
```

```swift
// En ExecApprovalDialog:
@FocusState private var focusedButton: ApprovalButton?

// .onAppear { focusedButton = .allowOnce }
```

### 6.4 Announcements para Cambios de Estado

| Evento | Announcement |
|--------|-------------|
| AI empieza a responder | "McClaw is responding" |
| AI termina de responder | "Response complete" |
| Voice mode: listening | "Listening" |
| Voice mode: speaking | "Speaking" |
| Gateway conectado/desconectado | "Gateway connected/disconnected" |
| Connector auth success/fail | "Connector X connected/failed" |
| Error de CLI | "Error: [message]" |
| Install progress | "Installing step X of Y" |

Implementar con `AccessibilityNotification.Announcement`:

```swift
AccessibilityNotification.Announcement(
    String(localized: "a11y_response_complete", bundle: .module)
).post()
```

---

## 7. Testing (Phase 5)

### 7.1 Tests Automatizados

Crear `McClaw/Tests/McClawTests/AccessibilityTests.swift`:

```swift
import XCTest
@testable import McClaw

final class AccessibilityTests: XCTestCase {

    // Verificar que botones icon-only tienen labels
    func testIconButtonsHaveAccessibilityLabels() {
        // Usar ViewInspector o snapshot testing
    }

    // Verificar que status indicators tienen labels
    func testStatusIndicatorsHaveLabels() { }

    // Verificar que Reduce Motion no crashea
    func testReduceMotionRendering() { }
}
```

### 7.2 Accessibility Identifiers (para XCUITest futuro)

Añadir `.accessibilityIdentifier()` a elementos clave:

```swift
// Formato: "area-element"
"chat-input-field"
"chat-send-button"
"chat-abort-button"
"sidebar-nav-chats"
"sidebar-nav-settings"
"sidebar-nav-schedules"
"message-bubble-\(message.id)"
"cli-selector-\(cli.id)"
"settings-tab-\(tab.id)"
"exec-approval-allow"
"exec-approval-deny"
```

### 7.3 Checklist Manual de VoiceOver

Ejecutar con VoiceOver activado (Cmd+F5):

1. [ ] **Sidebar** — Navegar todos los items con Tab/Arrow keys, verificar que se anuncian con su badge
2. [ ] **Nuevo chat** — Focus se mueve al input, VoiceOver anuncia el placeholder
3. [ ] **Enviar mensaje** — Botón Send se anuncia, VoiceOver indica "McClaw is responding"
4. [ ] **Recibir respuesta** — Al completar, VoiceOver anuncia "Response complete"
5. [ ] **Copiar mensaje** — Action bar accesible sin hover, botón Copy se anuncia
6. [ ] **Slash commands** — Popup se anuncia como lista, navegación con flechas funciona
7. [ ] **Settings** — Todas las tabs navegables, toggles/sliders anuncian sus valores
8. [ ] **Git panel** — Repos, branches, PRs se leen con información combinada
9. [ ] **Voice overlay** — Estado (listening/speaking) se anuncia
10. [ ] **Exec approval** — Dialog modal, focus en Allow Once, todos los botones claros

---

## 8. Convenciones para Vistas Nuevas

### Checklist obligatorio para toda vista nueva:

```
□ Botones icon-only tienen .iconButtonLabel()
□ Status indicators (círculos, badges) tienen .accessibilityLabel() con el estado
□ Elementos custom (Canvas, shapes) tienen .accessibilityLabel() o .accessibilityHidden(true)
□ Listas con múltiples datos usan .accessibilityElement(children: .combine)
□ Elemento seleccionado usa .accessibilityAddTraits(.isSelected)
□ Dimensiones fijas usan @ScaledMetric
□ Animaciones usan .motionSafeAnimation() o check reduceMotion
□ Colores de estado usan Theme.status* (no literales .green/.red)
□ Hover-to-reveal usa .hoverReveal(isHovering:)
□ Cambios de estado importantes postean AccessibilityNotification.Announcement
□ Strings de accesibilidad usan String(localized: "a11y_*", bundle: .module)
□ Elementos clave tienen .accessibilityIdentifier() para testing
```

### Principios:

1. **VoiceOver primero**: Si no puedes usar la vista con los ojos cerrados, falta accesibilidad
2. **Dynamic Type**: Si subes el texto a XXL y la UI se rompe, faltan `@ScaledMetric`
3. **Reduce Motion**: Si hay animación continua o decorativa, debe poder desactivarse
4. **No sobre-annotate**: Los controles estándar de SwiftUI (`Button` con texto, `TextField` con label, `Toggle`) ya son accesibles — solo anotar lo que SwiftUI no puede inferir

---

## 9. Estimación por Fases

| Fase | Scope | Archivos | Prioridad |
|------|-------|----------|-----------|
| 0 — Infraestructura | AccessibilityModifiers.swift, Theme.swift | 2 nuevos, 1 edit | Prerequisito |
| 1 — Chat Core | ChatInputBar, MessageBubbleView, ChatWindow, ChatSidebar, + 4 más | ~8 edits | Crítica |
| 2 — Settings | SettingsWindow, Connector*, Cron*, MCP*, + 6 más | ~10 edits | Alta |
| 3 — Especializadas | Git (13), Canvas, Voice, Security, Onboarding, Menu, Install | ~22 edits | Media |
| 4 — Motion/Contrast | ~18 archivos con animaciones, Theme.swift, MarkdownContentView | ~15 edits | Media |
| 5 — Testing | 1 test file, identifiers en ~10 archivos, doc checklist | ~11 edits | Alta |

**Total estimado**: ~2 nuevos archivos, ~65 archivos editados, ~80 localization keys nuevas.

---

## 10. Referencias

- [Apple Human Interface Guidelines — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [SwiftUI Accessibility API](https://developer.apple.com/documentation/swiftui/view-accessibility)
- [WCAG 2.1 AA](https://www.w3.org/TR/WCAG21/) — Nivel objetivo mínimo
- [macOS VoiceOver User Guide](https://support.apple.com/guide/voiceover/welcome/mac)
