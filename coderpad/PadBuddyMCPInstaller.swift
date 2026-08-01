import Foundation
import MCPClientInstall

#if os(macOS)
    import AppKit
#endif

extension MCPDesktopClient {
    var padBuddyRestartHint: String {
        switch self {
        case .claudeDesktop:
            String(localized: "Quit Claude Desktop with ⌘Q and reopen it, then ask it about your pads.")
        case .claudeCode:
            String(localized: "Start a fresh Claude Code session (or run /mcp), then ask it about your pads.")
        case .codex:
            String(localized: "Restart Codex, then ask it about your pads.")
        case .cursor:
            String(localized: "Reload Cursor (or toggle the server in its MCP settings), then ask it about your pads.")
        }
    }

    var padBuddyVerifyHint: String? {
        verifyHint(serverName: "padbuddy")
    }

    func padBuddySnippet(executablePath: String) -> String {
        configSnippet(for: PadBuddyMCPInstaller.server(executablePath: executablePath))
    }
}

enum PadBuddyMCPInstaller {
    nonisolated static let backupSuffix = ".padbuddy-backup"
    nonisolated static let preRestoreSuffix = ".padbuddy-before-restore"

    static func server(executablePath: String) -> MCPServerSpec {
        MCPServerSpec(
            name: "padbuddy",
            command: executablePath,
            productName: "PadBuddy",
            backupSuffix: backupSuffix
        )
    }

    #if !os(macOS)
        @MainActor
        static func install(_: MCPDesktopClient, executablePath _: String) async {}
    #endif

    #if os(macOS)
        struct ConfigSpec {
            let preferred: URL?
            let fallback: URL?
            let fileName: String
            let format: MCPClientInstall.ConfigurationFormat
            let message: String
        }

        static var realHomeDirectory: URL {
            if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
                return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }

        static func spec(for client: MCPDesktopClient) -> ConfigSpec {
            let home = realHomeDirectory
            let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
            switch client {
            case .claudeDesktop:
                return ConfigSpec(
                    preferred: support.appendingPathComponent("Claude", isDirectory: true),
                    fallback: support,
                    fileName: "claude_desktop_config.json",
                    format: .json,
                    message: String(localized: "Select Claude Desktop's “Claude” folder so PadBuddy can add itself.")
                )

            case .claudeCode:
                return ConfigSpec(
                    preferred: home,
                    fallback: home,
                    fileName: ".claude.json",
                    format: .json,
                    message: String(localized: "Select your Home folder so PadBuddy can add itself to ~/.claude.json.")
                )

            case .codex:
                return ConfigSpec(
                    preferred: home.appendingPathComponent(".codex", isDirectory: true),
                    fallback: home,
                    fileName: "config.toml",
                    format: .codexTOML,
                    message: String(localized: "Select the “.codex” folder so PadBuddy can add itself to config.toml.")
                )

            case .cursor:
                return ConfigSpec(
                    preferred: home.appendingPathComponent(".cursor", isDirectory: true),
                    fallback: home,
                    fileName: "mcp.json",
                    format: .json,
                    message: String(localized: "Select the “.cursor” folder so PadBuddy can add itself to mcp.json.")
                )
            }
        }

        @MainActor
        static func install(_ client: MCPDesktopClient, executablePath: String) async {
            guard MCPClientInstall.isRunnableExecutable(executablePath) else {
                showMissingExecutableAlert(for: client)
                return
            }

            let spec = spec(for: client)
            guard let folder = grantFolderAccess(spec: spec) else { return }
            guard folder.startAccessingSecurityScopedResource() else {
                showAlert(.warning, String(localized: "Could not update \(client.displayName)"), String(localized: """
                macOS did not grant PadBuddy access to that folder. Choose the client's configuration \
                folder again and allow access when prompted.
                """))
                return
            }

            defer { folder.stopAccessingSecurityScopedResource() }

            do {
                let configFolder = try configurationFolder(
                    granted: folder,
                    preferred: spec.preferred,
                    fallback: spec.fallback
                )
                guard confirmFolderIfUnexpected(configFolder, spec: spec, client: client) else { return }

                let url = configFolder.appendingPathComponent(spec.fileName)
                let server = server(executablePath: executablePath)
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try MCPClientInstall.prepareServerUpdate(server, format: spec.format, at: url)
                }.value
                if prepared.alreadyPresent, !confirmUpdate(client) {
                    return
                }

                _ = try await Task.detached(priority: .userInitiated) {
                    try MCPClientInstall.installServer(
                        server,
                        format: spec.format,
                        at: url,
                        backupSuffix: backupSuffix
                    )
                }.value
                let title = prepared.alreadyPresent
                    ? String(localized: "Updated \(client.displayName)")
                    : String(localized: "Added to \(client.displayName)")
                showAlert(.informational, title, client.padBuddyRestartHint)
            } catch {
                showAlert(
                    .warning,
                    String(localized: "Could not update \(client.displayName)"),
                    workflowMessage(error, fileName: spec.fileName)
                )
            }
        }

        @MainActor
        static func restorePreviousConfiguration(for client: MCPDesktopClient) async {
            let spec = spec(for: client)
            guard let folder = grantFolderAccess(
                spec: spec,
                message: String(localized: """
                Select \(client.displayName)'s configuration folder to restore its PadBuddy backup.
                """)
            ) else { return }
            guard folder.startAccessingSecurityScopedResource() else {
                showAlert(
                    .warning,
                    String(localized: "Could not restore \(client.displayName)"),
                    String(localized: "macOS did not grant PadBuddy access to that folder.")
                )
                return
            }

            defer { folder.stopAccessingSecurityScopedResource() }

            do {
                let configFolder = try configurationFolder(
                    granted: folder,
                    preferred: spec.preferred,
                    fallback: spec.fallback
                )
                let url = configFolder.appendingPathComponent(spec.fileName)
                _ = try await Task.detached(priority: .userInitiated) {
                    try MCPClientInstall.restoreBackup(
                        at: url,
                        backupSuffix: backupSuffix,
                        displacedSuffix: preRestoreSuffix
                    )
                }.value
                showAlert(.informational, String(localized: "Restored \(client.displayName)"), String(localized: """
                The previous configuration is active again. The replaced file remains beside it as \
                \(spec.fileName)\(preRestoreSuffix).
                """))
            } catch {
                showAlert(
                    .warning,
                    String(localized: "Could not restore \(client.displayName)"),
                    workflowMessage(error, fileName: spec.fileName)
                )
            }
        }

        static func configurationFolder(
            granted: URL,
            preferred: URL?,
            fallback: URL?,
            fileManager: FileManager = .default
        ) throws -> URL {
            guard let preferred, let fallback,
                  granted.standardizedFileURL == fallback.standardizedFileURL,
                  preferred.deletingLastPathComponent().standardizedFileURL == fallback.standardizedFileURL,
                  !fileManager.fileExists(atPath: preferred.path)
            else { return granted }

            try fileManager.createDirectory(at: preferred, withIntermediateDirectories: false)
            return preferred
        }

    #endif
}
