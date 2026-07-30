//
//  ConfigFileSecurity.swift
//  CoderPadMCPCore
//

import Darwin
import Foundation

func validatedConfigAttributes(
    path: String,
    explicit: Bool,
    fileManager: FileManager
) throws -> [FileAttributeKey: Any]? {
    let attributes: [FileAttributeKey: Any]
    do {
        attributes = try fileManager.attributesOfItem(atPath: path)
    } catch {
        let loadError = classifiedConfigReadError(path: path, error: error)
        if loadError == .missingConfig(path: path), !explicit { return nil }
        throw loadError
    }
    guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
        throw MCPConfigLoadError.symbolicLink(path: path)
    }
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
        throw MCPConfigLoadError.notRegularFile(path: path)
    }
    guard attributes[.ownerAccountID] as? UInt32 == geteuid() else {
        throw MCPConfigLoadError.wrongOwner(path: path)
    }
    guard let permissions = attributes[.posixPermissions] as? Int,
          permissions & 0o077 == 0 else {
        throw MCPConfigLoadError.insecurePermissions(path: path)
    }
    guard try !hasExtendedACL(path: path) else {
        throw MCPConfigLoadError.insecurePermissions(path: path)
    }

    return attributes
}

private func hasExtendedACL(path: String) throws -> Bool {
    errno = 0
    guard let acl = acl_get_file(path, ACL_TYPE_EXTENDED) else {
        if errno == ENOENT { return false }
        throw MCPConfigLoadError.readFailed(path: path)
    }

    acl_free(UnsafeMutableRawPointer(acl))
    return true
}

func configFileSize(path: String, attributes: [FileAttributeKey: Any]) throws -> Int64 {
    guard let size = attributes[.size] as? Int64 else {
        throw MCPConfigLoadError.readFailed(path: path)
    }

    return size
}

func classifiedConfigReadError(path: String, error: any Error) -> MCPConfigLoadError {
    let cocoa = error as? CocoaError
    switch cocoa?.code {
    case .fileReadNoSuchFile:
        return .missingConfig(path: path)
    case .fileReadNoPermission:
        return .permissionDenied(path: path)
    default:
        return .readFailed(path: path)
    }
}
