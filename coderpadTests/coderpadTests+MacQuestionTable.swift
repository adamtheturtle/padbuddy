#if os(macOS)
    @testable import CoderPad
    import Testing

    @Suite("Mac question table behavior")
    struct MacQuestionTableTests {
        @Test
        func `scroll request is honored once until cleared`() {
            var request = MacQuestionScrollRequest<Int>()

            let first = request.consume(42)
            let repeated = request.consume(42)
            #expect(first)
            #expect(!repeated)
            request.reset()
            let afterReset = request.consume(42)
            #expect(afterReset)
        }

        @Test
        func `missing scroll target remains pending`() {
            var request = MacQuestionScrollRequest<Int>()
            let missingTarget = 42
            let rows: [Int: Int] = [:]

            if rows[missingTarget] != nil { _ = request.consume(missingTarget) }

            #expect(request.activeID == nil)
            let consumed = request.consume(missingTarget)
            #expect(consumed)
        }

        @Test
        func `empty top row is reported initially and after content disappears`() {
            var report = MacQuestionTopRowReport<Int>()

            let initialEmpty = report.consume(nil)
            let repeatedEmpty = report.consume(nil)
            let firstRow = report.consume(7)
            let repeatedRow = report.consume(7)
            let becameEmpty = report.consume(nil)
            #expect(initialEmpty)
            #expect(!repeatedEmpty)
            #expect(firstRow)
            #expect(!repeatedRow)
            #expect(becameEmpty)
        }
    }
#endif
