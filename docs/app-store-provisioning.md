# Validate App Store distribution configuration

Xcode Cloud owns App Store Connect uploads.
The GitHub App Store workflow deliberately disables signing and only validates archive contents;
its success does not verify paid-team certificates, provisioning or upload permission.

Before distributing a build, download the **signed distribution archive** from the successful
Xcode Cloud build and run:

```sh
python3 scripts/check-appstore-provisioning.py /path/to/PadBuddy.xcarchive --team YOUR_TEAM_ID
```

The check verifies the code signature, distribution certificate type, embedded profile expiration,
team and exact application identifier (including legacy prefixes), debugger restrictions, and Mac App Store sandbox entitlement.
It rejects development, ad hoc and enterprise profiles.
Run it separately for each platform's signed archive.
An unsigned archive, a development build or a simulator build cannot satisfy this gate.

Record the source commit, Xcode Cloud build URL, archive platform, team ID and successful command
output in the release record before assigning the build to a TestFlight group.
Then verify App Store Connect has accepted that build and completed processing.
Do not copy signing keys or profile contents into the release record.

This offline check does not establish that App Store Connect agreements are current or that the
operator has upload and TestFlight permissions; verify those in App Store Connect.
If the signed archive is unavailable, leave distribution verification pending.
Fixture validation is available with `python3 scripts/test-appstore-provisioning.py`.

Apple documents why an [App ID prefix can differ from the team ID](https://developer.apple.com/library/archive/technotes/tn2311/).
The validator checks both independently.
