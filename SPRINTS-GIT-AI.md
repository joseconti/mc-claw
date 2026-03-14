# McClaw - Git Integration with AI (Doc 16.2) Sprint Tracker

## Documento de referencia
- Especificacion: `docs/McClaw/16.2-GIT-INTEGRATION-WITH-IA.md`
- Plan de implementacion: `.claude/plans/majestic-inventing-key.md`
- Base existente: `docs/McClaw/16-GIT-INTEGRATION.md` (ya implementado: Sprint 22)

## Estado General

| Sprint | Nombre | Estado | Progreso |
|--------|--------|--------|----------|
| A | Execution Pipeline | COMPLETADO | 9/9 |
| B | Contextual Actions | COMPLETADO | 9/9 |
| C | Intelligent Features | COMPLETADO | 6/6 |
| D | Monitoring & Advanced | COMPLETADO | 8/8 |

**Total**: 32/32 tareas completadas

---

## Sprint A: Execution Pipeline (Critical Path)

> **Goal**: AI propone write actions -> usuario ve confirmation cards -> ejecuta al confirmar -> resultados vuelven al AI.
> **Dependencias**: Ninguna (es el primero)
> **Archivos nuevos**: `PendingGitAction.swift`
> **Archivos modificados**: `ChatModels.swift`, `PromptEnrichmentService.swift`, `ChatViewModel.swift`, `GitActionConfirmationCard.swift`, `MessageBubbleView.swift`, `GitService.swift`, `Localizable.strings`

### Tareas

- [x] **A1** - Crear modelo `PendingGitAction.swift` en `Models/Git/`
  - PendingGitAction struct (id, type, command, title, details, status)
  - GitActionType enum (.localGit, .platformAPI)
  - GitActionStatus enum (.pendingConfirmation, .executing, .completed, .failed, .cancelled)

- [x] **A2** - Anadir `gitActions: [PendingGitAction]` a `ChatMessage`
  - Nuevo property en ChatMessage
  - Anadir a init con default []
  - Anadir a CodingKeys
  - Anadir a init(from decoder:) con decodeIfPresent

- [x] **A3** - Implementar parsing de `@git-confirm` y `@fetch-confirm` en `PromptEnrichmentService`
  - detectGitConfirmations(in:) -> [PendingGitAction]
  - detectFetchConfirmations(in:) -> [PendingGitAction]
  - removeConfirmationCommands(from:) -> String
  - Actualizar buildGitContextHeader con formato mejorado (READ/WRITE separados, instrucciones de confirmacion)

- [x] **A4** - Cablear deteccion de confirmaciones en `ChatViewModel.streamAndEnrich`
  - Nuevo bloque de intercepcion post-streaming para @git-confirm/@fetch-confirm
  - Detectar, limpiar texto, asignar a assistantMessage.gitActions
  - Metodo confirmGitAction(messageId:, actionId:) - ejecuta y envia resultado al AI
  - Metodo cancelGitAction(messageId:, actionId:) - cancela e informa al AI

- [x] **A5** - Actualizar `GitActionConfirmationCard` para todos los estados
  - Cambiar interface para aceptar PendingGitAction directamente
  - Renderizar .pendingConfirmation (botones Confirm/Cancel)
  - Renderizar .executing (ProgressView)
  - Renderizar .completed (checkmark verde + output)
  - Renderizar .failed (X roja + error)
  - Renderizar .cancelled (texto gris)
  - Banner de warning para operaciones destructivas (reset, rebase, --force)

- [x] **A6** - Renderizar cards de git action en `MessageBubbleView`
  - ForEach sobre message.gitActions
  - GitActionConfirmationCard con callbacks onConfirm/onCancel
  - Anadir closures onConfirmGitAction/onCancelGitAction a MessageBubbleView
  - Actualizar call sites para pasar closures desde ChatViewModel

- [x] **A7** - Seguridad: validacion de comandos y filtrado de contenido sensible
  - Set writeCommands en GitService
  - isWriteCommand() helper
  - containsSensitiveContent() - detecta API keys, tokens, passwords
  - Filtrar output antes de retornar
  - Bloquear --force en push/reset

- [x] **A8** - Localizacion Sprint A
  - git_action_executing, git_action_completed, git_action_failed
  - git_action_cancelled, git_action_destructive_warning
  - git_action_confirm, git_action_cancel

- [x] **A9** - Verificacion Sprint A
  - swift build pasa
  - swift test pasa
  - Test manual: seleccionar repo -> pedir crear branch -> card aparece -> confirmar -> ejecuta

---

## Sprint B: Contextual Actions

> **Goal**: Cada elemento UI (PR, issue, commit, branch, archivo) tiene acciones "Ask AI" via context menus.
> **Dependencias**: Sprint A completado
> **Archivos nuevos**: `GitPromptTemplates.swift`, `ContextualAction.swift`
> **Archivos modificados**: `GitPanelViewModel.swift`, `GitPRListView.swift`, `GitIssueListView.swift`, `GitCommitListView.swift`, `GitBranchListView.swift`, `GitFileContentView.swift`, `GitRepoDetailView.swift`, `GitPanelView.swift`, `Localizable.strings`

### Tareas

- [x] **B1** - Crear `GitPromptTemplates.swift` en `Models/Git/`
  - Prompt templates para PRs (6): review, summarize, suggest, conflicts, post review, merge
  - Prompt templates para Issues (5): analyze, suggest fix, create branch, close, find related
  - Prompt templates para Commits (4): explain, impact, revert, cherry-pick
  - Prompt templates para Branches (4): compare, create PR, delete, merge
  - Prompt templates para Files (4): explain, find usages, suggest improvements, write tests
  - Prompt template para seleccion de lineas (1)
  - Prompt templates repo-level (8): explain repo, what changed, what broke, changelog, health, security, todos, commit assistant

- [x] **B2** - Crear `ContextualAction.swift` en `Models/Git/`
  - ContextualAction struct (id, label, icon, prompt, autoSend)

- [x] **B3** - Anadir `sendToChat` a `GitPanelViewModel`
  - Closure onSendToChat: ((String, Bool) -> Void)?
  - Metodo sendToChat(prompt:, autoSend:)
  - Cablear en GitPanelView con chatViewModel

- [x] **B4** - Anadir context menus a todas las list views
  - GitPRListView: 6 acciones (Review, Summarize, Suggest, Post Review, Merge + separadores)
  - GitIssueListView: 5 acciones (Analyze, Suggest Fix, Create Branch, Close + separadores)
  - GitCommitListView: 4 acciones (Explain, Impact, Revert, Cherry-pick)
  - GitBranchListView: 4 acciones (Compare, Create PR, Delete, Merge)
  - Cada view recibe onSendToChat: (String) -> Void

- [x] **B5** - Anadir seleccion de lineas a `GitFileContentView`
  - @State selectedLineStart/selectedLineEnd
  - Lineas de numeros clicables (tap + shift-tap para rango)
  - Highlight de lineas seleccionadas con color accent
  - Boton flotante "Ask AI about lines X-Y" como overlay
  - Context menu a nivel de archivo: Explain, Find Usages, Suggest Improvements, Write Tests
  - Parametro onSendToChat

- [x] **B6** - Actualizar `GitRepoDetailView` para propagar `onSendToChat`
  - Nuevo parametro onSendToChat: (String) -> Void
  - Pasar a todas las sub-vistas (PR, Issue, Commit, Branch, FileContent)
  - Pasar info de defaultBranch para templates de branch

- [x] **B7** - Actualizar `GitPanelView` para proveer sendToChat
  - Pasar closure a GitRepoDetailView y GitRepoListView
  - Auto-expandir chat si esta colapsado al enviar prompt

- [x] **B8** - Localizacion Sprint B
  - ~30 strings para labels de context menu

- [x] **B9** - Verificacion Sprint B
  - swift build + swift test pasan
  - Click derecho en PR -> "Review this PR" -> chat abre con prompt
  - Seleccionar lineas -> boton flotante aparece -> envia prompt

---

## Sprint C: Intelligent Features & Action Bar

> **Goal**: Features AI avanzados a nivel de repositorio y quick actions.
> **Dependencias**: Sprint B completado (necesita sendToChat y templates)
> **Archivos nuevos**: `GitRepoActionBar.swift`, `GitQuickActionsPanel.swift`
> **Archivos modificados**: `GitRepoDetailView.swift`, `GitPanelView.swift`, `Localizable.strings`

### Tareas

- [x] **C1** - Crear `GitRepoActionBar.swift` en `Views/Git/`
  - ScrollView horizontal con HStack de botones capsule
  - 7 botones: Explain Repo, What Broke?, Changelog, Health Check, Security Audit, Find TODOs, This Week
  - Cada boton con icono SF Symbol + label localizado
  - Props: onSendToChat

- [x] **C2** - Integrar action bar en `GitRepoDetailView`
  - Insertar GitRepoActionBar entre header y tab bar
  - Pasar onSendToChat

- [x] **C3** - Crear `GitQuickActionsPanel.swift` en `Views/Git/`
  - Panel flotante con 5 acciones comunes
  - Commit changes, Pull latest, Create branch, Review open PRs, Generate changelog
  - Cada accion: expande chat + envia prompt

- [x] **C4** - Integrar quick actions en `GitPanelView`
  - Mostrar como overlay cuando: chat colapsado + repo seleccionado
  - Click en accion -> expandir chat -> enviar prompt

- [x] **C5** - Localizacion Sprint C
  - ~15 strings para action bar + quick actions

- [x] **C6** - Verificacion Sprint C
  - swift build + swift test pasan (799/799)
  - Action bar visible en repo detail debajo del header
  - Quick actions aparecen cuando chat colapsado con repo seleccionado
  - Cada boton envia prompt correcto

---

## Sprint D: Monitoring & Advanced

> **Goal**: Monitoring de repos via CronJobs, inteligencia cross-repo, resolucion de conflictos merge, cadenas multi-paso.
> **Dependencias**: Sprint A (para cadenas), Sprint B (para templates de merge conflicts)
> **Archivos nuevos**: `GitMonitorTemplate.swift`, `GitMonitorSetupSheet.swift`
> **Archivos modificados**: `GitPanelViewModel.swift`, `ChatViewModel.swift`, `GitModels.swift`, `PromptEnrichmentService.swift`, `Localizable.strings`

### Tareas

- [x] **D1** - Crear `GitMonitorTemplate.swift` en `Models/Git/`
  - GitMonitorTemplate struct (id, name, description, icon, defaultCronExpression, promptTemplate)
  - 6 templates estaticos: PR Reviewer, CI Watcher, Stale Branch Cleaner, Security Scan, Activity Summary, Issue Triage

- [x] **D2** - Crear `GitMonitorSetupSheet.swift` en `Views/Git/`
  - Sheet con grid de template cards
  - Selector de schedule (reusar patron de CronJobEditor)
  - Boton "Create Monitor"

- [x] **D3** - Cablear creacion de monitores a `CronJobsStore`
  - GitPanelViewModel.createMonitor(template:, cronExpression:)
  - Resolver connector instanceId
  - Crear ConnectorBinding
  - Construir CronJob y guardar
  - @State showingMonitorSheet en ViewModel

- [x] **D4** - Multi-step chain handling
  - ChatViewModel: chainDepth counter
  - Incrementar en cada confirmacion que triggerea nueva respuesta AI
  - Max depth: 10 (prevenir loops infinitos)
  - Reset a 0 cuando usuario envia nuevo mensaje

- [x] **D5** - Cross-repo intelligence
  - GitContext: anadir additionalRepos: [GitRepoInfo]?
  - PromptEnrichmentService: incluir repos adicionales en header
  - GitPanelViewModel: cmd+click para seleccion multiple de repos

- [x] **D6** - Merge conflict resolution
  - Anadir mergeConflictResolution() a GitPromptTemplates
  - Usar pipeline existente: @git(status) -> @git(show :1/:2/:3:file) -> @git-confirm(add)

- [x] **D7** - Localizacion Sprint D
  - ~25 strings para monitor templates, sheet labels

- [x] **D8** - Verificacion Sprint D
  - Monitor button abre setup sheet
  - Crear monitor crea CronJob visible en Schedules
  - Cadena multi-paso funciona (step 1 -> confirm -> step 2 -> confirm -> ...)
  - Cross-repo context muestra ambos repos en header

---

## Notas para Cambio de Chat

**Al empezar un nuevo chat para continuar el desarrollo:**

1. Lee este archivo (`SPRINTS-GIT-AI.md`) para ver el estado actual
2. Lee el plan (`.claude/plans/majestic-inventing-key.md`) para los detalles de implementacion
3. Lee `docs/McClaw/16.2-GIT-INTEGRATION-WITH-IA.md` para la especificacion completa
4. Busca la primera tarea marcada como `- [ ]` y continua desde ahi
5. Despues de completar cada tarea, marca como `- [x]` y actualiza la tabla de progreso

**Convencion**: Al completar un sprint entero, actualizar la tabla de Estado General cambiando PENDIENTE -> COMPLETADO y el progreso a X/X.
