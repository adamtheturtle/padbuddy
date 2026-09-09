# App Privacy Answers

Use these answers in App Store Connect's App Privacy section.

| Question | Answer |
| --- | --- |
| Does the app collect data from this app? | No |
| Is data used for tracking? | No |
| Tracking domains | None |
| Third-party advertising | No |
| Analytics | No |
| Developer-operated backend | No |
| Account creation in this app | No |
| Account deletion requirement | Not applicable; the app does not create developer-operated accounts |

The app stores the user's CoderPad API key as a synchronizable Apple Keychain item.
Apple may synchronize it across the user's trusted devices when iCloud Keychain is enabled.
The app otherwise sends it only directly to CoderPad's API at the user's configured server URL.
This is user-provided credential storage for app functionality, not developer data collection.

The bundled privacy manifest declares:

- `NSPrivacyTracking = false`
- no tracking domains
- no collected data types
- UserDefaults access for app functionality
