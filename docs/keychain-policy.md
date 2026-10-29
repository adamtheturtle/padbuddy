# Credential Keychain policy

PadBuddy stores account snapshots as generic-password items under the service `com.adamdangoor.padbuddy`.

The app deliberately does not set `kSecAttrAccessGroup` and none of its app or widget entitlements declares `keychain-access-groups`.
Credentials therefore remain in the app’s implicit signing-identity group and are not available to either Recent Pads widget.
Widget handoff uses the App Group’s non-secret snapshot files instead.

Local credentials use the legacy macOS Keychain through `BuddyAppKit.KeychainStore`, retaining the platform’s default item accessibility.
This is required for the profile-less Developer ID build: switching to the data-protection Keychain or declaring a sharing group requires a provisioning-profile application identifier and previously caused `errSecMissingEntitlement` or prevented launch.
A stable signed release can read its items after the user grants Keychain access; debug rebuilds may prompt again when their signature changes.

The optional iCloud mirror uses synchronizable generic-password items with the same service and no explicit access group.
Missing synchronizable entitlement is tolerated for Developer ID builds, while the local item remains authoritative.

`scripts/check-keychain-policy.swift` is run before Xcode Cloud archives.
It fails if any app or widget entitlement gains a Keychain sharing group, or if the app begins setting an explicit access group without an intentional policy and provisioning update.

Unit-test hosts and launches with `-uiTesting` use in-memory accounts and skip credential persistence and iCloud mirroring.
