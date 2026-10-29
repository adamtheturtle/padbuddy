# Agent workflow

Fetch `origin/main` before creating a feature worktree.

For macOS visual checks, build and launch the app with:

```sh
bash scripts/run-demo.sh
```

This starts a new instance with `-uiTesting`, an in-memory demo account, and no credential persistence.
Use `bash scripts/run-demo.sh -uiTestingNoAccounts` to check first-run and account-setup screens.
When another launch tool is necessary, pass `-uiTesting` explicitly.
The command prints its app path and PID; use these to identify your demo instance.
Check that it is running before attaching UI inspection tools, which may otherwise launch a normal instance without arguments.
Close only the demo instance you launched when finished.
Opening a Debug or test-host app without that flag can access the user's real Keychain and show authorization prompts after a rebuild.

Use real accounts only when the requested task requires them.
A Keychain prompt during a demo or automated test indicates missing isolation: fix the launch or test setup without granting access to personal credentials.
Keep the project's signing configuration for normal builds; real-account use can require macOS authorization.

Run `./scripts/preflight.sh` before pushing code changes.
Follow the test-tier guidance in [CONTRIBUTING.md](CONTRIBUTING.md), preferring unit or render coverage for behavior that does not need a full app launch.
