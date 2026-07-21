//
//  MCPClientInstall+Restore.swift
//  coderpad
//

#if os(macOS)
    import AppKit

    extension MCPClientInstall {
        /// Restores the configuration that was present before PadBuddy's most
        /// recent rewrite. A fresh folder grant keeps this recovery path within
        /// the same sandbox boundary as installation.
        @MainActor
        static func restorePreviousConfiguration(for client: Client) async {
            let spec = spec(for: client)
            guard let folder = grantFolderAccess(
                preferred: spec.preferred,
                fallback: spec.fallback,
                message: "Select \(client.displayName)'s configuration folder to restore its PadBuddy backup."
            ) else { return }
            guard folder.startAccessingSecurityScopedResource() else {
                showAlert(.warning, "Could not restore \(client.displayName)",
                          "macOS did not grant PadBuddy access to that folder.")
                return
            }

            defer { folder.stopAccessingSecurityScopedResource() }

            do {
                let configFolder = try configurationFolder(
                    granted: folder, preferred: spec.preferred, fallback: spec.fallback
                )
                let url = configFolder.appendingPathComponent(spec.fileName)
                try await Task.detached(priority: .userInitiated) {
                    try restoreConfigBackup(at: url)
                }.value
                showAlert(.informational, "Restored \(client.displayName)", String(localized: """
                The previous configuration is active again. The replaced file remains beside it as \
                \(spec.fileName)\(preRestoreSuffix).
                """))
            } catch {
                showAlert(.warning, "Could not restore \(client.displayName)", error.localizedDescription)
            }
        }
    }
#endif
