import LocalAuthentication
import SwiftUI

extension AccountEditor {
    /// Reveals or hides the Interview API key after device-owner authentication.
    func toggleReveal() {
        toggleReveal(of: $revealKey, reason: String(localized: "Reveal your saved CoderPad API key"))
    }

    /// Reveals or hides the optional Screen API key with the same protection.
    func toggleScreenReveal() {
        toggleReveal(
            of: $revealScreenKey,
            reason: String(localized: "Reveal your saved CoderPad Screen API key")
        )
    }

    private func toggleReveal(of revealed: Binding<Bool>, reason: String) {
        if revealed.wrappedValue {
            revealAuthenticationTask?.cancel()
            revealed.wrappedValue = false
            return
        }

        revealAuthenticationTask?.cancel()
        revealAuthenticationTask = Task {
            let authenticated = await authenticateForReveal(reason: reason)
            guard authenticated, !Task.isCancelled else { return }

            revealed.wrappedValue = true
        }
    }

    func concealSecrets() {
        revealAuthenticationTask?.cancel()
        revealAuthenticationTask = nil
        revealKey = false
        revealScreenKey = false
    }

    private func authenticateForReveal(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
