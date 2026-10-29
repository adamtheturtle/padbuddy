#!/usr/bin/env python3
"""Validate a signed App Store archive without accessing signing credentials."""
import argparse
import datetime
import pathlib
import plistlib
import subprocess


def validate_profile(profile, entitlements, team, bundle, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, datetime.datetime):
        raise ValueError("Provisioning profile has no expiration date")
    if expiry.replace(tzinfo=datetime.timezone.utc) <= now:
        raise ValueError("Provisioning profile has expired")
    if team not in profile.get("TeamIdentifier", []):
        raise ValueError("Provisioning profile belongs to another team")
    if profile.get("ProvisionedDevices") is not None or profile.get("ProvisionsAllDevices"):
        raise ValueError("A development, ad hoc or enterprise profile cannot prove App Store distribution")
    profile_entitlements = profile.get("Entitlements", {})
    app_id = profile_entitlements.get("application-identifier", profile_entitlements.get("com.apple.application-identifier"))
    expected_ids = [f"{prefix}.{bundle}" for prefix in profile.get("ApplicationIdentifierPrefix", [])]
    if app_id not in expected_ids:
        raise ValueError("The profile application identifier does not match its declared prefix and bundle")
    for values, label in [(profile_entitlements, "profile"), (entitlements, "signature")]:
        if values.get("get-task-allow") or values.get("com.apple.security.get-task-allow"):
            raise ValueError(f"The {label} permits debugger attachment")
        identifier = values.get("application-identifier", values.get("com.apple.application-identifier"))
        if identifier != app_id:
            raise ValueError(f"The {label} application identifier does not match the requested team and bundle")
        if values.get("com.apple.developer.team-identifier") != team:
            raise ValueError(f"The {label} team entitlement does not match")
    if "OSX" in profile.get("Platform", []) and not entitlements.get("com.apple.security.app-sandbox"):
        raise ValueError("Mac App Store apps must enable App Sandbox")


def command(*arguments):
    result = subprocess.run(arguments, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f"{arguments[0]} could not validate the supplied archive")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=pathlib.Path, help="A signed .xcarchive or .app")
    parser.add_argument("--team", required=True, help="Expected paid Apple Developer team identifier")
    args = parser.parse_args()
    try:
        apps = [args.archive] if args.archive.suffix == ".app" else list(
            (args.archive / "Products/Applications").glob("*.app")
        )
        if len(apps) != 1:
            raise ValueError("Expected exactly one archived application")
        app = apps[0]
        contents = app / "Contents" if (app / "Contents").is_dir() else app
        with (contents / "Info.plist").open("rb") as stream:
            bundle = plistlib.load(stream)["CFBundleIdentifier"]
        command("codesign", "--verify", "--deep", "--strict", str(app))
        signature = command("codesign", "-dvv", str(app)).stderr.decode(errors="replace")
        authorities = ("Authority=Apple Distribution:", "Authority=3rd Party Mac Developer Application:")
        if not any(line.startswith(authorities) for line in signature.splitlines()):
            raise ValueError("The app needs an App Store distribution signature, not a development or ad hoc signature")
        entitlements = plistlib.loads(command("codesign", "-d", "--entitlements", ":-", str(app)).stdout)
        profiles = [contents / "embedded.provisionprofile", contents / "embedded.mobileprovision"]
        profile_path = next((path for path in profiles if path.is_file()), None)
        if profile_path is None:
            raise ValueError("The signed app has no embedded distribution provisioning profile")
        profile = plistlib.loads(command("security", "cms", "-D", "-i", str(profile_path)).stdout)
        validate_profile(profile, entitlements, args.team, bundle)
        print(f"Verified offline App Store signing/profile checks for {bundle} and team {args.team}.")
    except (ValueError, OSError, KeyError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"App Store provisioning validation failed: {error}\n")


if __name__ == "__main__":
    main()
