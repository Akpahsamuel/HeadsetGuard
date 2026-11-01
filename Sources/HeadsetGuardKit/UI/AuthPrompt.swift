import AppKit

/// Modal master-PIN prompt for actions that must not be available to whoever is sitting at an
/// unlocked Mac (changing protections, clearing the log, quitting the guard).
enum AuthPrompt {
    /// Returns true when the PIN verifies, or when no PIN is configured yet.
    static func requestPIN(message: String) -> Bool {
        let sm = SecurityManager.shared
        guard sm.isPasswordConfigured else { return true }

        let cooldown = sm.lockoutRemaining()
        if cooldown > 0 {
            showFailure("Too many failed attempts. Try again in \(Int(cooldown.rounded(.up)))s.")
            return false
        }

        let alert = NSAlert()
        alert.messageText = "Authentication Required"
        alert.informativeText = message
        alert.addButton(withTitle: "Authorize")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        if sm.verifyPassword(field.stringValue) { return true }
        let left = sm.lockoutRemaining()
        showFailure(left > 0
                    ? "Too many failed attempts. Try again in \(Int(left.rounded(.up)))s."
                    : "Incorrect PIN/password.")
        return false
    }

    private static func showFailure(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
