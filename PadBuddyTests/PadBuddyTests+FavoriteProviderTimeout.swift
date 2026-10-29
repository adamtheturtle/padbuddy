import Foundation
@testable import PadBuddy
import Testing
import UniformTypeIdentifiers

@Suite("Favorite provider deadlines")
struct FavoriteProviderTimeoutTests {
    @Test func `nonresponsive reorder provider reaches the deadline`() async {
        let provider = NSItemProvider()
        let type = UTType.coderpadFavoriteReorder.identifier
        provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { _ in nil }
        let result = await Sidebar.loadFavoritePayload(provider, typeIdentifier: type, timeout: .milliseconds(10))
        #expect(result == nil)
    }

    @Test func `late provider completion cannot replace timeout result`() async {
        let provider = NSItemProvider()
        let type = UTType.coderpadFavoriteReorder.identifier
        provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                completion(Data("late".utf8), nil)
            }
            return nil
        }
        let result = await Sidebar.loadFavoritePayload(provider, typeIdentifier: type, timeout: .milliseconds(10))
        #expect(result == nil)
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test func `responsive provider returns its payload`() async {
        let provider = NSItemProvider()
        let type = UTType.coderpadFavoriteReorder.identifier
        let payload = Data("reorder".utf8)
        provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
            completion(payload, nil)
            return nil
        }
        #expect(await Sidebar.loadFavoritePayload(provider, typeIdentifier: type) == payload)
    }
}
