# TODO

Tracking follow-ups for the CoderPad macOS app.

## Blocking — do first

- [ ] **Enable App Sandbox → Outgoing Connections (Client)** in Xcode (Signing & Capabilities tab on the `coderpad` target). Until this is ticked, every API call fails with `NSURLErrorDomain -1003` ("hostname could not be found").
- [ ] **End-to-end verification**: Run the app, open Settings, paste a valid CoderPad API key, confirm the pad list loads and selection shows the detail form.

## Cleanup

- [ ] Delete leftover SwiftData scaffolding: `coderpad/coderpad/Item.swift` and the `ModelContainer` setup in `coderpad/coderpad/coderpadApp.swift`. Nothing uses it.
- [ ] Rename `coderpad/coderpad/Secrets.swift` → `APIKeyStore.swift`. The file no longer holds a secret; it's a Keychain-backed store.

## Features

- [ ] **Validate API key on Save** in `SettingsView`. Call `GET /api/organization` with the entered key; show a green check + org name on success, a clear error otherwise.
- [ ] **Handle HTTP 401 specifically** in `ContentView`. Instead of the raw error string, show a "Key invalid — open Settings" CTA that opens the Settings sheet.
- [ ] **Pad events**: fetch `GET /api/pads/:id/events` and render on `PadDetailView`.
- [ ] **Filter/sort the pads list**: by state (started/ended), by owner, by `updated_at`.

## Testing

- [ ] Unit tests for the `Pad` decoder covering missing keys, null values, and ISO8601 date parsing. Use the Swift Testing framework, not XCTest.

## Security / hygiene

- [ ] **Rotate the CoderPad API key** that was pasted into chat earlier. It's in the conversation transcript; treat as compromised.
- [ ] Move from default Keychain item to one explicitly scoped to the app's keychain access group (currently relies on the default Generic Password class).
