# Privacy Policy

_Last updated: 2026-07-13_

This privacy policy describes how the **PadBuddy** app for Mac, iPhone, and iPad
("the app") handles your information. The app is an unofficial, third-party
client for [CoderPad](https://coderpad.io); it is not affiliated with,
endorsed by, or operated by CoderPad, Inc.

## Summary

The app does not collect, transmit, or sell any personal data. There is no
analytics, no advertising, no tracking, and no developer-operated server. The
app talks only to CoderPad's own API, using an API key that you supply.

## What the app stores, and where

- **Your CoderPad API key** is stored only in the **local Keychain** on
  your device. It never leaves your device except in requests sent directly to
  CoderPad's API to fetch and manage your own data.
- **App preferences and a local cache** (for example, your selected account,
  the last-viewed section, saved searches, favorite questions, and a cache of
  pads/questions so the app opens quickly) are stored locally on your device in
  standard app storage. None of this is uploaded anywhere by the app.

## What the app sends, and to whom

When you use the app, it makes requests directly from your device to CoderPad's
API (`https://app.coderpad.io`, or a self-hosted/regional URL if you configure
one) to read and manage the pads, questions, organization, and quota that your
CoderPad account already has access to. Those requests are authenticated with
the API key you provide.

CoderPad's own handling of that data is governed by CoderPad's privacy policy,
not this one.

## Data collection

The app collects **no** data on behalf of the developer. Its bundled
`PrivacyInfo.xcprivacy` manifest declares no tracking, no tracking domains, and
no collected data types.

## Children

The app contains no objectionable content and is suitable for all ages. It does
not knowingly collect any information from anyone, including children.

## Your control

You can remove your API key and all locally stored data at any time by removing
the account in the app's Settings, or by deleting the app. There are no
developer-side accounts to delete, because the app never creates any.

## Contact

Questions about this policy can be sent to **hello@adamdangoor.com** or raised
on the project's issue tracker:
<https://github.com/adamtheturtle/coderpad-macos/issues>.
