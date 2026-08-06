# Privacy Policy

_Last updated: 2026-07-29_

This privacy policy describes how the **PadBuddy** app for Mac, iPhone, and iPad
("the app") handles your information. The app is an unofficial, third-party
client for [CoderPad](https://coderpad.io); it is not affiliated with,
endorsed by, or operated by CoderPad, Inc.

## Summary

The app does not collect, transmit, or sell any personal data. There is no
analytics, no advertising, no tracking, and no developer-operated server. The
app talks only to CoderPad's own API, using an API key that you supply.

## What the app stores, and where

- **Your CoderPad API key** is stored in Apple's Keychain as a synchronizable
  item. If iCloud Keychain is enabled for your Apple Account, Apple may
  synchronize it across your trusted devices. The app otherwise sends the key
  only in requests directly to your configured CoderPad API.
- **Selected preferences and favorites** can synchronize through Apple's iCloud
  key-value store when iCloud is available. This includes pad/question sorting
  and filters, saved-search state, appearance, notification and browser
  preferences, favorite pad/question identifiers, and favorite ordering. Apple
  processes this sync under your Apple Account settings.
- **Cached CoderPad content and device-specific UI state** stay in the app's
  local container and are not uploaded by the app.

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

You can remove your API key and local account data at any time by removing the
account in the app's Settings. Removing an account also removes its
account-scoped favorites from the app's iCloud store. You can stop further
preference and favorite synchronization by disabling iCloud access for PadBuddy
in your system Apple Account settings. Deleting the app removes its local data;
Apple controls retention of synchronized Keychain and iCloud data. There are no
developer-side accounts to delete, because the app never creates any.

## Contact

Questions about this policy can be sent to **hello@adamdangoor.com** or raised
on the project's issue tracker:
<https://github.com/adamtheturtle/padbuddy/issues>.
