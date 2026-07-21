@testable import CoderPad
import Testing

@Suite("Welcome presentation")
struct WelcomePresentationTests {
    @Test
    func `accountless windows always show welcome`() {
        #expect(WelcomePresentationPolicy.shouldShow(
            hasAccounts: false,
            arguments: [],
            isDebugBuild: false
        ))
    }

    @Test
    func `debug launch argument forces welcome with a configured account`() {
        #expect(WelcomePresentationPolicy.shouldShow(
            hasAccounts: true,
            arguments: ["PadBuddy", "-showWelcome"],
            isDebugBuild: true
        ))
    }

    @Test
    func `release builds ignore the development launch argument`() {
        #expect(!WelcomePresentationPolicy.shouldShow(
            hasAccounts: true,
            arguments: ["PadBuddy", "-showWelcome"],
            isDebugBuild: false
        ))
    }

    @Test
    func `configured account uses normal content without launch argument`() {
        #expect(!WelcomePresentationPolicy.shouldShow(
            hasAccounts: true,
            arguments: [],
            isDebugBuild: true
        ))
    }
}
