import Foundation

/// A contextual AI action that can be triggered from UI elements (context menus, buttons).
struct ContextualAction: Identifiable, Sendable {
    let id: String
    let label: String
    let icon: String
    let prompt: String
    /// If true, the prompt is sent immediately. If false, it's pre-filled in the input bar.
    let autoSend: Bool

    init(id: String = UUID().uuidString, label: String, icon: String, prompt: String, autoSend: Bool = true) {
        self.id = id
        self.label = label
        self.icon = icon
        self.prompt = prompt
        self.autoSend = autoSend
    }
}
