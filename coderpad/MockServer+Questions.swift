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
        [fizzBuzzQuestion(), urlShortenerQuestion(), concurrencyDraftQuestion()]
    }

    private static func fizzBuzzQuestion() -> [String: Any] {
        let instructions = "Print numbers 1-100 with Fizz/Buzz rules."
        return [
            "id": 101,
            "title": "FizzBuzz",
            "owner_email": "alex@demo.co",
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
            "author_name": "Alex Park", "organization_name": "Demo Org",
            "created_at": "2025-09-01T10:00:00Z", "updated_at": "2026-06-08T10:00:00Z"
        ]
    }

    private static func urlShortenerQuestion() -> [String: Any] {
        [
            "id": 102,
            "title": "URL shortener (take-home)",
            "owner_email": "morgan@demo.co",
            "language": "go",
            "description": urlShortenerDescription(),
            "candidate_instructions": [
                ["instructions": urlShortenerInstructions(), "default_visible": true]
            ],
            "shared": true, "used": 5, "take_home": true,
            "test_cases_enabled": false, "solution": urlShortenerSolution(),
            "pad_type": "take-home", "is_draft": false,
            "public_take_home_setting_id": 7421,
            "contents": urlShortenerContents(), "custom_files": [],
            "author_name": "Morgan Lin", "organization_name": "Demo Org",
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
            "owner_email": "alex@demo.co",
            "language": "rust",
            "description": NSNull(),
            "candidate_instructions": [["instructions": "", "default_visible": true]],
            "shared": false, "used": 0, "take_home": false,
            "test_cases_enabled": false, "solution": "",
            "pad_type": "live", "is_draft": true,
            "contents": NSNull(), "custom_files": [],
            "author_name": "Alex Park", "organization_name": "Demo Org",
            "created_at": "2026-06-05T11:00:00Z", "updated_at": "2026-06-05T11:00:00Z"
        ]
    }

    // The starter code a candidate begins from. The plain `contents` prints its
    // output, while the test-cases variant returns a value so the harness can
    // assert on it — exercising both "Starter Code" cards in the question detail.
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
