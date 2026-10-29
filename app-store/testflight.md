# CoderPad team TestFlight beta

Track distribution in [issue #204](https://github.com/adamtheturtle/padbuddy/issues/204).
The repository contains a public beta link, but that link alone does not verify a current build, its tester group, or invitations to CoderPad employees.
Keep the issue open until the following App Store Connect outcomes are verified.

## Build and group

1. Use the existing Xcode Cloud distribution workflow described in [XCODE_CLOUD.md](../XCODE_CLOUD.md).
   Archive the Sparkle-free `PadBuddy-AppStore` scheme in `AppStoreRelease` and verify the exported product with the [provisioning check](../docs/app-store-provisioning.md).
2. Confirm the upload has finished processing in App Store Connect.
   Record its platform, version, build number, source commit, and Xcode Cloud build URL.
3. Use an external TestFlight group named **CoderPad team** for CoderPad people who are not App Store Connect users.
   An existing internal group is also required before creating an external group.
   A build exported as **TestFlight Internal Only** cannot be promoted to external testing; use a new export eligible for external distribution.
4. Add the processed build to the group and paste the [What to Test note](submission/en-US/testflight-what-to-test.txt).
   Complete the existing beta contact and review information and submit for TestFlight App Review when required.
5. Once the build is eligible for testing, invite the supplied CoderPad tester email addresses to that group.
   Verify the group membership and invitation state in App Store Connect.
   TestFlight access does not require granting external testers App Store Connect roles.

Apple documents [external tester groups and build eligibility](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers) and [adding groups to builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-testers-to-builds/).

## Completion evidence

Record these outcomes in the issue without publishing tester email addresses:

- The processed platform/version/build and its source commit.
- Successful paid-team export validation and the Xcode Cloud build URL.
- The CoderPad team group with the intended build available for testing.
- The testing note saved on that build.
- The intended recipients present with invitations sent or accepted.

A local unsigned archive, Simulator build, prepared testing note, existing public link, or merged documentation PR is not evidence that these distribution steps completed.
