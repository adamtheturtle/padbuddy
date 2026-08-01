#if os(macOS)
    import AppKit
    import MCPClientInstall

    extension PadBuddyMCPInstaller {
        @MainActor
        static func grantFolderAccess(spec: ConfigSpec, message: String? = nil) -> URL? {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: "Grant Access")
            panel.message = message ?? spec.message
            if let preferred = spec.preferred, FileManager.default.fileExists(atPath: preferred.path) {
                panel.directoryURL = preferred
            } else {
                panel.directoryURL = spec.fallback
            }
            return panel.runModal() == .OK ? panel.url : nil
        }

        @MainActor
        static func confirmFolderIfUnexpected(
            _ folder: URL,
            spec: ConfigSpec,
            client: MCPDesktopClient
        ) -> Bool {
            let target = folder.appendingPathComponent(spec.fileName)
            if FileManager.default.fileExists(atPath: target.path) {
                return true
            }
            if let preferred = spec.preferred,
               preferred.standardizedFileURL == folder.standardizedFileURL {
                return true
            }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Create \(spec.fileName) here?")
            alert.informativeText = String(localized: """
            That folder does not look like \(client.displayName)'s configuration folder and has no \
            \(spec.fileName) in it yet. PadBuddy would create one at \(target.path).
            """)
            alert.addButton(withTitle: String(localized: "Create"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            return alert.runModal() == .alertFirstButtonReturn
        }

        @MainActor
        static func confirmUpdate(_ client: MCPDesktopClient) -> Bool {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = String(localized: "Update \(client.displayName)?")
            alert.informativeText = String(localized: """
            \(client.displayName) already has a “padbuddy” server. Update it to launch this copy of PadBuddy?
            """)
            alert.addButton(withTitle: String(localized: "Update"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            return alert.runModal() == .alertFirstButtonReturn
        }

        @MainActor
        static func showMissingExecutableAlert(for client: MCPDesktopClient) {
            showAlert(.warning, "Could not update \(client.displayName)", String(localized: """
            PadBuddy could not find its own program file, so it cannot tell \(client.displayName) \
            where to find it. Move PadBuddy to your Applications folder and try again.
            """))
        }

        static func workflowMessage(_ error: any Error, fileName: String) -> String {
            guard let error = error as? MCPClientInstall.InstallWorkflowError else {
                return error.localizedDescription
            }

            switch error {
            case let .unsafePath(_, kind):
                return MCPClientInstall.refusalReason(for: kind, fileName: fileName)
                    ?? "PadBuddy left the configuration unchanged."

            case let .configurationTooLarge(_, limit):
                return "The existing configuration is larger than \(limit) bytes. PadBuddy left it unchanged."

            case let .invalidConfiguration(_, detail):
                if fileName.hasSuffix(".toml") {
                    return String(localized: """
                    config.toml is not valid TOML — \(detail). PadBuddy will not add to a file it cannot read, \
                    because Codex would still refuse to load it. Fix that line and try again.
                    """)
                }
                return String(localized: """
                The existing JSON configuration does not have a compatible mcpServers server object. \
                PadBuddy left it unchanged.
                """)

            case .verificationFailed:
                return "PadBuddy could not verify the written server entry. The previous file remains in the backup."

            case .backupUnavailable:
                return "No PadBuddy backup was found beside this configuration file."

            case .displacedFileExists:
                return "The pre-restore recovery file already exists. PadBuddy left every file unchanged."

            case let .readFailed(_, detail),
                 let .serializationFailed(_, detail),
                 let .writeFailed(_, detail),
                 let .restorationFailed(_, detail):
                return detail
            }
        }

        @MainActor
        static func showAlert(_ style: NSAlert.Style, _ title: String, _ message: String) {
            let alert = NSAlert()
            alert.alertStyle = style
            alert.messageText = title
            alert.informativeText = message
            alert.runModal()
        }
    }
#endif
