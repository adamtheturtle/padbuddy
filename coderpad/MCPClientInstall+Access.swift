//
//  MCPClientInstall+Access.swift
//  coderpad
//

#if os(macOS)
    import AppKit

    extension MCPClientInstall {
        /// The user's real home directory. A sandbox's FileManager home points into
        /// its container; getpwuid remains the host user's actual home.
        static var realHomeDirectory: URL {
            if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
                return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }

        /// Prompts for a security-scoped config-folder grant, starting at the exact
        /// client folder when it exists or its existing parent otherwise.
        @MainActor
        static func grantFolderAccess(preferred: URL?, fallback: URL?, message: String) -> URL? {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Grant Access"
            panel.message = message
            if let preferred, FileManager.default.fileExists(atPath: preferred.path) {
                panel.directoryURL = preferred
            } else {
                panel.directoryURL = fallback
            }
            return panel.runModal() == .OK ? panel.url : nil
        }
    }
#endif
