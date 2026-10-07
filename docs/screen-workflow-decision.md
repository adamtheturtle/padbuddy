# Screen Workflow Decision

Tracking issue: [#687](https://github.com/adamtheturtle/padbuddy/issues/687)

PadBuddy treats CoderPad Screen as a native monitoring and operations surface for the API workflows the app can perform safely, and uses web handoff only for workflows not exposed by the current Screen API client.

## Native Workflows

| Workflow | Native Status | Implementation |
|---|---|---|
| Create campaign | Native for a single account | `ScreenCampaignCreationSheet`, selected/random questions and optional settings, `ScreenClient.createCampaign(_:)` |
| Browse Screen questions and insights | Native for a single account | `ScreenQuestionBankView`, UUID detail, filters and pagination |
| List campaigns | Native | `ScreenCampaignsView`, `MergedScreenView`, `ScreenClient.listCampaigns()` |
| Search/filter campaigns | Native | Campaign search binding and Show Archived toolbar toggle |
| List test sessions | Native | `ScreenTestsView`, `ScreenClient.listAllTests(campaignID:from:)` |
| Filter test sessions by status/date/search | Native | Status menu, date range menu, shared search field |
| Invite candidate | Native | `ScreenInviteSheet`, `ScreenClient.sendInvitation(campaignID:_:)` |
| Resend waiting invitation | Native | Test row context menu, commands, `ScreenClient.resendTest(id:)` |
| Cancel waiting invitation | Native | Test row context menu, commands, `ScreenClient.cancelTest(id:)` |
| Delete test session | Native | Test row context menu with confirmation, `ScreenClient.deleteTest(id:)` |
| Open report in separate window | Native | `ScreenTestWindow`, `ScreenTestDetailView` |
| Export/view report PDF | Native | `ScreenClient.testReport(id:...)` used by the report detail surface |
| Configure webhook | Native for a single account | `ScreenWebhookSheet`, `ScreenClient.webhookURL()`, `setWebhookURL(_:)`, `deleteWebhook()` |
| Copy campaign/test summaries | Native | Focused Screen commands and row context menus |

## Web Or Unsupported Workflows

| Workflow | Decision | Reason |
|---|---|---|
| Campaign editing | Not native yet | Creation is supported. The client has no campaign editing endpoint. |
| Campaign archive/pin mutation | Not native yet | The API model exposes `pinned` and `archived`, but the current client has no mutation endpoint. |
| Bulk test-session operations | Not native yet | Single-row resend/cancel/delete exists; bulk operations need product design and API-rate/error handling. |
| Merged-account webhook configuration | Single-account only | A webhook belongs to one Screen account/organization, so configuration stays on the single-account campaign list. |

## Platform Policy

| Platform | Policy |
|---|---|
| macOS | Use native split view, menus, customizable toolbars, context menus, and separate report windows. |
| Regular-width iPad | Use the shared split view and toolbar/menu affordances where available. |
| Compact iPad and iPhone | Use the compact tab/navigation-stack shell; Screen remains reachable when credentials exist. |
| Merged accounts | Aggregate campaign/test visibility, but keep account-scoped write actions routed to the selected campaign's owning account. |

## Follow-Ups

Create focused issues only when a concrete API-backed workflow is confirmed:

- Add native campaign archive/pin/edit actions if the Screen API supports them.
- Add bulk resend/cancel/delete only after designing partial-failure UI.
- Add richer report sharing/export controls if user testing shows the current report surface is insufficient.
