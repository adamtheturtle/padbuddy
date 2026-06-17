//
//  MockServer+Environments.swift
//  coderpad
//
//  Canned pad-environment fixtures: each id is a distinct environment so a
//  single pad can carry several languages and a mix of single- and multi-file
//  layouts. Split out of MockServer.swift to keep files within the limits.
//

import Foundation

nonisolated extension MockFixtures {
    static func padEnvironment(id: Int) -> [String: Any] {
        // Ids 2 and 4 are multi-file to exercise the per-file tabs and the "N files"
        // count; id 4 mixes HTML/CSS/JS so the per-file, extension-derived
        // highlighting is visible (each file rendered in its own language, not the
        // environment's).
        let environment = environmentFiles(id: id)
        return [
            "id": id,
            "pad_id": 88_112_233,
            "question_id": NSNull(),
            "example_question_id": NSNull(),
            "language": environment.language,
            "file_contents": environment.files,
            "created_at": "2026-06-09T18:00:00Z",
            "updated_at": "2026-06-09T18:00:00Z"
        ]
    }

    private static func file(_ path: String, _ contents: String) -> [String: Any] {
        ["path": path, "contents": contents, "history": NSNull()]
    }

    private static func environmentFiles(id: Int) -> (language: String, files: [[String: Any]]) {
        switch id {
        case 1:
            return ("python3", [
                file("coderpad/main.py",
                     "def greet(name):\n    return f\"Hello, {name}!\"\n\nprint(greet(\"CoderPad\"))\n")
            ])

        case 3:
            let swift = "import Foundation\n\nfunc greet(_ name: String) -> String {\n"
                + "    \"Hello, \\(name)!\"\n}\n\nprint(greet(\"CoderPad\"))\n"
            return ("swift", [file("main.swift", swift)])

        case 4:
            // A small mixed-language web project: each file is highlighted in its
            // own language (HTML, CSS, JavaScript) from its extension, even though
            // the environment reports a single language.
            return ("javascript", webProjectFiles())

        default: // 2 and any other id
            return ("javascript", [
                file("src/index.js",
                     "import { greet } from './greet.js';\n\nconsole.log(greet('CoderPad'));\n"),
                file("src/greet.js",
                     "export function greet(name) {\n  return `Hello, ${name}!`;\n}\n")
            ])
        }
    }

    private static func webProjectFiles() -> [[String: Any]] {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <title>Greeter</title>
            <link rel="stylesheet" href="styles.css" />
          </head>
          <body>
            <h1 id="greeting">Hello</h1>
            <script src="app.js"></script>
          </body>
        </html>

        """
        let css = """
        body {
          font-family: -apple-system, sans-serif;
          margin: 2rem;
        }

        #greeting {
          color: #2d6cdf;
          font-weight: 600;
        }

        """
        let javascript = """
        function greet(name) {
          return `Hello, ${name}!`;
        }

        document.getElementById('greeting').textContent = greet('CoderPad');

        """
        return [
            file("index.html", html),
            file("styles.css", css),
            file("app.js", javascript)
        ]
    }
}
