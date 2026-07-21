#if os(macOS)
    @testable import CoderPad
    import Testing

    @Suite("Mac question table behavior")
    struct MacQuestionTableTests {
        @Test
        func `scroll request is honored once until cleared`() {
            var request = MacQuestionScrollRequest<Int>()

            #expect(request.consume(42))
            #expect(!request.consume(42))
            request.reset()
            #expect(request.consume(42))
        }

        @Test
        func `missing scroll target remains pending`() {
            var request = MacQuestionScrollRequest<Int>()
            let missingTarget = 42
            let rows: [Int: Int] = [:]

            if rows[missingTarget] != nil { _ = request.consume(missingTarget) }

            #expect(request.activeID == nil)
            #expect(request.consume(missingTarget))
        }

        @Test
        func `empty top row is reported initially and after content disappears`() {
            var report = MacQuestionTopRowReport<Int>()

            #expect(report.consume(nil))
            #expect(!report.consume(nil))
            #expect(report.consume(7))
            #expect(!report.consume(7))
            #expect(report.consume(nil))
        }
    }
#endif
