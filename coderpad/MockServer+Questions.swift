//
//  MockServer+Questions.swift
//  coderpad
//
//  The canned question library for the fake API. Split out of MockServer.swift
//  to keep each file within the line and body-length limits.
//

import Foundation

nonisolated extension MockFixtures {
    static func questions() -> [[String: Any]] {
        [
            fizzBuzzQuestion(),
            urlShortenerQuestion(),
            concurrencyDraftQuestion(),
            question(id: 104, title: "Two Sum", ownerEmail: "sybil@fawltytowers.co.uk",
                     author: "Sybil Fawlty", language: "python3", used: 67,
                     description: "Return the indices of the two numbers that add up to a target.",
                     createdAt: "2025-08-14T10:00:00Z", updatedAt: "2026-06-07T12:00:00Z"),
            question(id: 105, title: "LRU Cache", ownerEmail: "basil@fawltytowers.co.uk",
                     author: "Basil Fawlty", language: "java", used: 23,
                     description: "Implement an LRU cache with O(1) get and put.",
                     createdAt: "2025-10-02T10:00:00Z", updatedAt: "2026-05-21T09:00:00Z"),
            question(id: 106, title: "Rate limiter (take-home)", ownerEmail: "manuel@fawltytowers.co.uk",
                     author: "Manuel", language: "go", used: 9, takeHome: true,
                     description: "Design a token-bucket rate limiter and justify the tradeoffs.",
                     createdAt: "2025-12-01T10:00:00Z", updatedAt: "2026-06-02T09:00:00Z"),
            question(id: 107, title: "Merge intervals", ownerEmail: demoUserEmail,
                     author: demoUserName, language: "typescript", used: 31,
                     description: "Merge all overlapping intervals and return the result.",
                     createdAt: "2025-09-19T10:00:00Z", updatedAt: "2026-06-06T09:00:00Z")
        ]
    }

    /// A compact, fully-formed question for the extra seed entries. The three
    /// richer questions below stay hand-written so the demo still shows multi-part
    /// instructions, test cases, custom files, and Markdown rendering.
    private static func question(id: Int, title: String, ownerEmail: String, author: String,
                                 language: String, used: Int, takeHome: Bool = false,
                                 description: String, createdAt: String, updatedAt: String) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "owner_email": ownerEmail,
            "language": language,
            "description": description,
            "candidate_instructions": [["instructions": description, "default_visible": true]],
            "shared": true, "used": used, "take_home": takeHome,
            "test_cases_enabled": false, "solution": "",
            "pad_type": takeHome ? "take-home" : "live", "is_draft": false,
            "contents": NSNull(), "custom_files": [],
            "author_name": author, "organization_name": MockFixtures.orgName,
            "created_at": createdAt, "updated_at": updatedAt
        ]
    }

    private static func fizzBuzzQuestion() -> [String: Any] {
        let instructions = "Print numbers 1-100 with Fizz/Buzz rules."
        return [
            "id": 101,
            "title": "FizzBuzz",
            "owner_email": "basil@fawltytowers.co.uk",
            "language": "python3",
            "description": "Classic warm-up problem.",
            "candidate_instructions": [["instructions": instructions, "default_visible": true]],
            "shared": true, "used": 42, "take_home": false,
            "test_cases_enabled": true, "solution": "see notion",
            "test_cases": [
                ["id": 1, "arguments": ["3"], "return_value": "Fizz", "visible": true],
                ["id": 2, "arguments": ["5"], "return_value": "Buzz", "visible": true],
                ["id": 3, "arguments": ["15"], "return_value": "FizzBuzz", "visible": false]
            ],
            "pad_type": "live", "is_draft": false,
            "contents": fizzBuzzContents(),
            "contents_for_test_cases": fizzBuzzTestCaseContents(),
            "custom_files": [
                ["id": "cf1", "title": "Starter", "description": "Boilerplate the candidate begins from",
                 "filename": "fizzbuzz.py", "filesize": "1.2 KB"],
                ["id": "cf2", "title": "Fixtures", "description": "Sample inputs for manual testing",
                 "filename": "cases.csv", "filesize": "640 B"]
            ],
            "author_name": "Basil Fawlty", "organization_name": MockFixtures.orgName,
            "created_at": "2025-09-01T10:00:00Z", "updated_at": "2026-06-08T10:00:00Z"
        ]
    }

    private static func urlShortenerQuestion() -> [String: Any] {
        [
            "id": 102,
            "title": "URL shortener (take-home)",
            "owner_email": "manuel@fawltytowers.co.uk",
            "language": "go",
            "description": urlShortenerDescription(),
            "candidate_instructions": [
                ["instructions": urlShortenerInstructions(), "default_visible": true],
                ["instructions": urlShortenerHint(), "default_visible": false]
            ],
            "shared": true, "used": 5, "take_home": true,
            "test_cases_enabled": false, "solution": urlShortenerSolution(),
            "pad_type": "take-home", "is_draft": false,
            "public_take_home_setting_id": 7421,
            "contents": urlShortenerContents(), "custom_files": [],
            "author_name": "Manuel", "organization_name": MockFixtures.orgName,
            "created_at": "2025-11-12T14:00:00Z", "updated_at": "2026-05-30T09:00:00Z"
        ]
    }

    private static func urlShortenerDescription() -> String {
        """
        # URL Shortener

        Design and ship a small, **production-minded** URL shortener service.

        ## Goals

        - Accept a long URL and return a short code
        - Redirect short codes back to the *original* URL
        - Survive a process restart (durable storage)

        ## Non-goals

        1. Custom vanity domains
        2. Analytics dashboards
        3. Multi-region replication — keep it **single node**

        See the [design rubric](https://example.com/rubric) before you start.
        """
    }

    private static func urlShortenerInstructions() -> String {
        """
        ## Candidate Instructions

        Read the spec, then **scope your solution** to ~45 minutes.

        ### What we provide

        | Component | Status |
        | --- | --- |
        | HTTP router | stubbed |
        | Storage interface | `Store` defined |

        ### Suggested API

        ```go
        type Store interface {
            Save(code, url string) error
            Lookup(code string) (string, bool)
        }
        ```

        > **Tip:** start with an in-memory map, then talk through how you'd
        > make it durable. Don't over-engineer the `encoding` up front.

        Checklist:

        - [x] Read the spec
        - [ ] Sketch the data model
        - [ ] Implement `POST /shorten`
        - [ ] Implement `GET /{code}`
        """
    }

    /// A second candidate-instruction part — hidden from the candidate by default —
    /// so the demo exercises both multi-part instruction separation and the
    /// "Hidden by default" badge.
    private static func urlShortenerHint() -> String {
        """
        ## Interviewer Hint

        If the candidate stalls, nudge them toward **collision handling**: what
        happens when two long URLs hash to the same code?

        A good answer mentions either a longer code space or a retry-on-conflict
        loop, and notes the tradeoff against `code` length.
        """
    }

    private static func urlShortenerSolution() -> String {
        """
        # Reference Solution

        A working solution typically has **three** pieces:

        1. A base-62 encoder for the auto-increment id
        2. A `Store` backed by SQLite (or a map for the demo)
        3. Two handlers wired into the router

        ## Encoding

        ```go
        const alphabet = "0123456789abcdefghijklmnopqrstuvwxyz" +
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

        func encode(n uint64) string {
            if n == 0 {
                return "0"
            }
            var b []byte
            for n > 0 {
                b = append([]byte{alphabet[n%62]}, b...)
                n /= 62
            }
            return string(b)
        }
        ```

        ## Things to probe in the interview

        - *Collision handling* when codes are generated randomly
        - Read-vs-write ratio and why a cache helps
        - What happens at `2^63` ids — see [overflow notes][1]

        [1]: https://example.com/overflow
        """
    }

    private static func concurrencyDraftQuestion() -> [String: Any] {
        [
            "id": 103,
            "title": "[DRAFT] Concurrency primitives",
            "owner_email": "terry@fawltytowers.co.uk",
            "language": "rust",
            "description": NSNull(),
            "candidate_instructions": [["instructions": "", "default_visible": true]],
            "shared": false, "used": 0, "take_home": false,
            "test_cases_enabled": false, "solution": "",
            "pad_type": "live", "is_draft": true,
            "contents": NSNull(), "custom_files": [],
            "author_name": "Terry Hughes", "organization_name": MockFixtures.orgName,
            "created_at": "2026-06-05T11:00:00Z", "updated_at": "2026-06-05T11:00:00Z"
        ]
    }

    /// The starter code a candidate begins from. The plain `contents` prints its
    /// output, while the test-cases variant returns a value so the harness can
    /// assert on it — exercising both "Starter Code" cards in the question detail.
    private static func fizzBuzzContents() -> String {
        """
        def fizzbuzz(n):
            # TODO: print Fizz/Buzz/FizzBuzz for each number from 1 to n
            pass


        if __name__ == "__main__":
            fizzbuzz(100)
        """
    }

    private static func fizzBuzzTestCaseContents() -> String {
        """
        def fizzbuzz(n):
            # TODO: return "Fizz", "Buzz", "FizzBuzz", or str(n)
            return ""
        """
    }

    private static func urlShortenerContents() -> String {
        """
        package main

        // Store persists the mapping from short code to original URL.
        type Store interface {
            Save(code, url string) error
            Lookup(code string) (string, bool)
        }

        func main() {
            // TODO: wire up POST /shorten and GET /{code}
        }
        """
    }
}
