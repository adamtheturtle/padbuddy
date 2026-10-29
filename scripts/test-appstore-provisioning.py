#!/usr/bin/env python3
"""Fixture checks for rejecting invalid distribution profiles."""
import copy
import datetime
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "provisioning", pathlib.Path(__file__).with_name("check-appstore-provisioning.py")
)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class DistributionProfileTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
        self.entitlements = {
            "application-identifier": "TEAM.com.example.app",
            "com.apple.developer.team-identifier": "TEAM",
            "get-task-allow": False,
        }
        self.profile = {
            "ExpirationDate": datetime.datetime(2027, 1, 1),
            "TeamIdentifier": ["TEAM"],
            "ApplicationIdentifierPrefix": ["TEAM"],
            "Entitlements": copy.deepcopy(self.entitlements),
        }

    def check(self):
        validator.validate_profile(self.profile, self.entitlements, "TEAM", "com.example.app", self.now)

    def test_matching_distribution_profile(self):
        self.check()

    def test_legacy_prefix_can_differ_from_team(self):
        self.profile["ApplicationIdentifierPrefix"] = ["LEGACY"]
        self.entitlements["application-identifier"] = "LEGACY.com.example.app"
        self.profile["Entitlements"]["application-identifier"] = "LEGACY.com.example.app"
        self.check()

    def test_expired_profile(self):
        self.profile["ExpirationDate"] = datetime.datetime(2025, 1, 1)
        with self.assertRaises(ValueError):
            self.check()

    def test_wrong_team(self):
        self.profile["TeamIdentifier"] = ["OTHER"]
        with self.assertRaises(ValueError):
            self.check()

    def test_device_profile(self):
        self.profile["ProvisionedDevices"] = ["test-device"]
        with self.assertRaises(ValueError):
            self.check()

    def test_debuggable_signature(self):
        self.entitlements["get-task-allow"] = True
        with self.assertRaises(ValueError):
            self.check()

    def test_wrong_signed_bundle(self):
        self.entitlements["application-identifier"] = "TEAM.com.other.app"
        with self.assertRaises(ValueError):
            self.check()


unittest.main()
