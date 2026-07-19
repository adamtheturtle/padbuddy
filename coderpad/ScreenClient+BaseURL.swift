//
//  ScreenClient+BaseURL.swift
//  coderpad
//

import Foundation

extension ScreenClient {
    nonisolated static func isAllowedBaseURL(_ url: URL) -> Bool {
        let allowedHosts = [defaultBaseURL.host, euBaseURL.host].compactMap { $0?.lowercased() }
        return url.scheme?.lowercased() == "https"
            && url.host.map { allowedHosts.contains($0.lowercased()) } == true
            && url.port == nil && url.user == nil && url.password == nil
            && url.query == nil && url.fragment == nil
            && (url.path.isEmpty || url.path == "/")
    }
}
