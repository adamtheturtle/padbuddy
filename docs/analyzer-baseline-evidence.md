# Analyzer baseline evidence

A full macOS SwiftLint 0.65.0 analyzer pass reported these 43 existing declarations.
Their uses are in tests, other platform branches, framework metadata, or synthesized `Hashable` code.
The table records the evidence for each added baseline entry.
The compiler-backed rules and complete shipping-source scan remain enabled.
New Interview and Screen declarations are outside these exceptions.

The same audit removed the unreferenced `lastOpened` and `isFinished` accessors.
Both focused-window tasks now capture a local constant that refers to the existing focus box.

| Source | Declaration | Reference evidence |
| --- | --- | --- |
| `PadBuddy/WidgetCompletedCreateLedger.swift` | `entries` | PadBuddyTests/PadBuddyTests+WidgetCompletedCreateLedger.swift |
| `PadBuddy/PadMutationRevisionStore.swift` | `trackedKeyCount` | PadBuddyTests/PadBuddyTests+PadMutationRevisions.swift |
| `PadBuddy/FocusFilter.swift` | `pop` | PadBuddyTests/PadBuddyTests+StateRestoration.swift |
| `PadBuddy/TVProvisioningRequest.swift` | `companionKeychainDeletionSucceeded` | PadBuddy/WatchApp.swift; PadBuddy/WatchProvisioningService.swift; PadBuddyTests/PadBuddyTests+TVProvisioning.swift |
| `PadBuddy/TVProvisioningRequest.swift` | `companionStatusBelongsToAccount` | PadBuddy/WatchApp.swift; PadBuddy/WatchProvisioningService.swift; PadBuddyTests/PadBuddyTests+TVProvisioning.swift |
| `PadBuddy/TVProvisioningRequest.swift` | `nextWatchProvisioningRevision` | PadBuddy/WatchApp.swift; PadBuddy/WatchProvisioningService.swift; PadBuddyTests/PadBuddyTests+TVProvisioning.swift |
| `PadBuddy/SettingsView+Models+Appearance.swift` | `label` | PadBuddyTests/PadBuddyTests+Settings.swift |
| `PadBuddy/SettingsView+Models+Appearance.swift` | `appearance` | PadBuddyTests/PadBuddyTests+Settings.swift |
| `PadBuddy/FocusFilter+Intent.swift` | `description` | AppIntents IntentDescription requirement |
| `PadBuddy/ScreenReportOperationLimiter.swift` | `hasQueuedWaiters` | PadBuddyTests/PadBuddyTests+ScreenCancellation.swift |
| `PadBuddy/CompanionCredentials.swift` | `encoded` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; PadBuddyTests/PadBuddyTests+TVProvisioning.swift |
| `PadBuddy/CompanionCredentials.swift` | `legacy` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; PadBuddyTests/PadBuddyTests+TVProvisioning.swift |
| `PadBuddy/PadDetailView+SaveCode+Focus.swift` | `sweepPadbuddyExportArchives` | PadBuddy/PadDetailView+SaveCode+Focus.swift; PadBuddyTests/PadBuddyTests+PadExportStaging.swift |
| `PadBuddy/PreferenceCloudSync+Revision.swift` | `deletionWins` | PadBuddy/PreferenceCloudSync.swift; PadBuddyTests/PadBuddyTests+PreferenceCloudSync.swift |
| `PadBuddy/PreferenceCloudSync+Revision.swift` | `mirrorReadbackMatches` | PadBuddy/PreferenceCloudSync.swift; PadBuddyTests/PadBuddyTests+PreferenceCloudSync.swift |
| `PadBuddy/PreferenceCloudSync+Revision.swift` | `retryShouldYieldToCloud` | PadBuddy/PreferenceCloudSync.swift; PadBuddyTests/PadBuddyTests+PreferenceCloudSync.swift |
| `PadBuddy/DockBadge.swift` | `badgeWriteDecision` | PadBuddy/DockBadge.swift; PadBuddyTests/PadBuddyTests+DockBadgeCompletion.swift |
| `PadBuddy/WidgetSharedStoreSafety.swift` | `loadData` | PadBuddyTests/PadBuddyTests+WidgetSharedStoreSafety.swift |
| `PadBuddy/SectionAvailabilitySettling.swift` | `shouldContinue` | PadBuddy/PhoneContentView.swift |
| `PadBuddy/IPadQuickActions.swift` | `deactivate` | PadBuddy/IPadQuickActions.swift; PadBuddyTests/PadBuddyTests+IPadQuickActions.swift |
| `PadBuddy/PadCodePreview+HighlightedCode.swift` | `embeddedHeight` | PadBuddyTests/PadBuddyTests+HighlightedCodeLayout.swift |
| `PadBuddy/NetworkConstraintMonitor.swift` | `hasResolvedPath` | PadBuddyTests/PadBuddyTests+NetworkConstraintMonitor.swift |
| `PadBuddy/NetworkConstraintMonitor.swift` | `stop` | PadBuddyTests/PadBuddyTests+NetworkConstraintMonitor.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `companionReadChunkBytes` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `usableDirectCompanionItems` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `CompanionItemID` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `boundedCompanionSearchInput` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `normalizedCompanionLanguage` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `normalizedCompanionTitle` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `invalidate` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `CompanionReloadTaskSlot` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `replace` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `cancel` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `CompanionPageToken` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/CompanionPlatformPolicy.swift` | `companionReloadWithTimeout` | PadBuddy/WatchApp.swift; PadBuddy/TVApp.swift; watchOS/tvOS section in PadBuddy/CompanionPlatformPolicy.swift; PadBuddyTests/PadBuddyTests+CompanionPlatformPolicy.swift |
| `PadBuddy/StandaloneWindowAccountResolution.swift` | `route` | Synthesized Hashable used by PadBuddy/PadWindow.swift, PadBuddy/QuestionWindow.swift, and PadBuddy/ScreenTestWindow.swift |
| `PadBuddy/StandaloneWindowAccountResolution.swift` | `clientIdentity` | Synthesized Hashable used by PadBuddy/PadWindow.swift, PadBuddy/QuestionWindow.swift, and PadBuddy/ScreenTestWindow.swift |
| `PadBuddy/PreferenceCloudSync+Validation.swift` | `shouldAdoptCloudValue` | PadBuddyTests/PadBuddyTests+PreferenceCloudSync.swift |
| `PadBuddy/AppReadiness.swift` | `waiterCount` | PadBuddyTests/PadBuddyTests+AppReadinessTimeout.swift |

The universal app-only compiler capture also reports four declarations used in the arm64 FoundationModels branch.
The x86_64 branch omits those callers.
Their tests and arm64 callers remain in the source.

| Source | Declaration | Reference evidence |
| --- | --- | --- |
| `PadBuddy/PadCodeExplainer.swift` | `maxCodeCharacters` | The arm64 FoundationModels generate and boundedExcerpt methods in the same file; PadBuddyTests/PadBuddyTests+QuestionDrafting.swift |
| `PadBuddy/QuestionDrafter.swift` | `usableSolution` | The arm64 FoundationModels generate method in the same file; PadBuddyTests/PadBuddyTests+QuestionDrafting.swift |
| `PadBuddy/OnDeviceModelParsing.swift` | `OnDeviceModelParsing` | The arm64 FoundationModels parsing in PadBuddy/PadCodeExplainer.swift and PadBuddy/QuestionDrafter.swift; PadBuddyTests/PadBuddyTests+ModelParsing.swift |
| `PadBuddy/OnDeviceModelParsing.swift` | `labeledSections` | The arm64 FoundationModels parsing in PadBuddy/PadCodeExplainer.swift and PadBuddy/QuestionDrafter.swift; PadBuddyTests/PadBuddyTests+ModelParsing.swift |
