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
            if FileManager.default.fileExists(atPath: spec.preferred.path) {
                panel.directoryURL = spec.preferred
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
            if spec.preferred.standardizedFileURL == folder.standardizedFileURL {
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
            showAlert(.warning, String(localized: "Could not update \(client.displayName)"), String(localized: """
            PadBuddy could not find its own program file, so it cannot tell \(client.displayName) \
            where to find it. Move PadBuddy to your Applications folder and try again.
            """))
        }

        static func workflowMessage(_ error: any Error, fileName: String) -> String {
            guard let error = error as? MCPClientInstall.InstallWorkflowError else {
                return String(localized: "PadBuddy could not complete the update — \(error.localizedDescription)")
            }

            return workflowMessage(error, fileName: fileName)
        }

        private static func workflowMessage(
            _ error: MCPClientInstall.InstallWorkflowError,
            fileName: String
        ) -> String {
            switch error {
            case let .unsafePath(_, kind):
                unsafePathMessage(kind, fileName: fileName)

            case let .configurationTooLarge(_, limit):
                String(localized: """
                The existing configuration is larger than \(limit) bytes. PadBuddy left it unchanged.
                """)

            case let .invalidConfiguration(_, detail):
                invalidConfigurationMessage(detail, fileName: fileName)

            case let .invalidServer(error):
                String(localized: "PadBuddy's server definition is invalid — \(String(describing: error))")

            case .configurationChanged:
                String(localized: "The configuration changed during the update. PadBuddy left it unchanged.")

            case .verificationFailed:
                String(localized: """
                PadBuddy could not verify the written server entry, so it restored the previous configuration.
                """)

            case .multiplyLinkedConfiguration, .writeCommitted, .verificationTargetChanged,
                 .verificationRollbackCleanupFailed, .restorationCommitted:
                protectedUpdateMessage(error)

            case .backupUnavailable:
                String(localized: "No PadBuddy backup was found beside this configuration file.")

            case .displacedFileExists:
                String(localized: """
                The pre-restore recovery file already exists. PadBuddy left every file unchanged.
                """)

            case .readFailed, .lockFailed, .serializationFailed, .writeFailed,
                 .verificationRollbackFailed, .invalidBackup, .unsafeSiblingSuffix,
                 .restorationFailed, .restorationRollbackFailed:
                detailedWorkflowMessage(error)
            }
        }

        private static func protectedUpdateMessage(
            _ error: MCPClientInstall.InstallWorkflowError
        ) -> String {
            switch error {
            case let .multiplyLinkedConfiguration(_, linkCount):
                String(localized: """
                The configuration has \(linkCount) filesystem links. PadBuddy left it unchanged because replacing it \
                could affect another path.
                """)

            case let .writeCommitted(_, backupURL, detail):
                writeCommittedMessage(backupURL: backupURL, detail: detail)

            case .verificationTargetChanged:
                String(localized: """
                The configuration changed after PadBuddy wrote it. PadBuddy preserved the newer file instead of \
                overwriting it during verification.
                """)

            case let .verificationRollbackCleanupFailed(_, displacedURL, detail):
                String(localized: """
                PadBuddy restored the previous configuration but could not remove the failed update at \
                \(displacedURL.path) — \(detail)
                """)

            case let .restorationCommitted(_, displacedURL, detail):
                String(localized: """
                PadBuddy restored the backup, but could not finish safely — \(detail). The previous configuration \
                remains at \(displacedURL.path).
                """)

            default:
                String(localized: "PadBuddy could not complete the configuration operation.")
            }
        }

        private static func detailedWorkflowMessage(
            _ error: MCPClientInstall.InstallWorkflowError
        ) -> String {
            switch error {
            case let .lockFailed(_, detail):
                String(localized: "PadBuddy could not lock the configuration for a safe update — \(detail)")

            case let .verificationRollbackFailed(_, _, detail):
                String(localized: "PadBuddy could not verify or fully roll back the update — \(detail)")

            case let .invalidBackup(_, detail):
                String(localized: "The PadBuddy backup is not a valid configuration — \(detail)")

            case .unsafeSiblingSuffix:
                String(localized: "PadBuddy refused an unsafe recovery filename.")

            case let .readFailed(_, detail):
                String(localized: "PadBuddy could not read the configuration — \(detail)")

            case let .serializationFailed(_, detail):
                String(localized: "PadBuddy could not prepare the updated configuration — \(detail)")

            case let .writeFailed(_, detail):
                String(localized: "PadBuddy could not write the configuration — \(detail)")

            case let .restorationFailed(_, detail):
                String(localized: "PadBuddy could not restore the configuration — \(detail)")

            case let .restorationRollbackFailed(_, _, _, detail):
                String(localized: """
                PadBuddy could not restore the configuration or put the displaced file back — \(detail)
                """)

            case .unsafePath, .configurationTooLarge, .invalidConfiguration,
                 .invalidServer, .configurationChanged, .multiplyLinkedConfiguration,
                 .writeCommitted, .verificationFailed, .verificationTargetChanged,
                 .verificationRollbackCleanupFailed, .backupUnavailable, .displacedFileExists,
                 .restorationCommitted:
                String(localized: "PadBuddy could not complete the configuration operation.")
            }
        }

        private static func writeCommittedMessage(backupURL: URL?, detail: String) -> String {
            if let backupURL {
                return String(localized: """
                The configuration was updated, but PadBuddy could not finish syncing the change safely — \(detail). \
                The previous configuration remains at \(backupURL.path).
                """)
            }
            return String(localized: """
            The configuration was updated, but PadBuddy could not finish syncing the change safely — \(detail).
            """)
        }

        private static func unsafePathMessage(_ kind: MCPClientInstall.ConfigPathKind, fileName: String) -> String {
            switch kind {
            case .absent, .regularFile:
                String(localized: "PadBuddy left the configuration unchanged.")

            case let .symbolicLink(destination):
                String(localized: """
                \(fileName) is a link to \(destination.isEmpty ? String(localized: "another location") : destination). \
                PadBuddy will not write through it because that could change a file outside the folder you selected. \
                Edit that file directly, or replace the link with a regular file.
                """)

            case .special:
                String(localized: """
                \(fileName) is not a regular file, so PadBuddy cannot read or replace it. Check the item at that path \
                and try again.
                """)

            case let .unavailable(detail):
                String(localized: "PadBuddy could not inspect \(fileName) safely — \(detail)")
            }
        }

        private static func invalidConfigurationMessage(_ detail: String, fileName: String) -> String {
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
