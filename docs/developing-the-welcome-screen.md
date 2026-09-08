# Developing the welcome screen

Use the dedicated `Welcome — Regular`, `Welcome — Compact`, and `Welcome — Dark` SwiftUI previews for layout and appearance work.
These previews construct `PadBuddyWelcomeView` directly and never read or modify saved accounts.

To exercise the welcome screen in the real macOS window:

1. Open **Product > Scheme > Edit Scheme…** in Xcode.
2. Select **Run > Arguments**.
3. Add and enable the launch argument `-showWelcome`.
4. Run a Debug build of PadBuddy.

The argument only changes which root view is presented.
Saved accounts remain in the Keychain and the **Add CoderPad Account** button continues to open the real Accounts settings flow.
Disable the argument to return to the selected account.
Release builds ignore the argument.
