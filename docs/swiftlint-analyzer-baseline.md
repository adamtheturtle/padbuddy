# SwiftLint analyzer baseline

CI analyzes every shipping source root with the macOS compiler log.
It checks unused declarations, closure captures, array initialization, and imports.
The declaration baseline records individual findings that this compiler log cannot resolve.
It does not disable a rule or exclude a source file.

The October 2026 repair updates existing entries after file moves and declaration changes.
It removes the closure-capture exception after changing the closures to capture constant references.
It also removes two unused helpers, `SingleResume.isFinished` and `PadOpenedStore.lastOpened`.

The additional declaration entries have these references:

| Declarations | References the macOS analyzer cannot resolve |
| --- | --- |
| `WidgetCompletedCreateLedger.entries`, `PadMutationRevisionStore.trackedKeyCount`, `ScreenReportOperationLimiter.hasQueuedWaiters`, `AppReadiness.waiterCount` | Assertions and synchronization in their test suites. |
| `FocusScopeStack.pop` | Focus restoration tests in `PadBuddyTests+StateRestoration.swift` and `PadBuddyTests+FocusScopeStackRestoration.swift`. |
| `companionKeychainDeletionSucceeded`, `companionStatusBelongsToAccount`, `nextWatchProvisioningRevision` | `WatchApp.swift`, `TVApp.swift`, and `WatchProvisioningService.swift`. |
| `CompanionCredentials.encoded`, `CompanionCredentials.legacy` | Credential persistence and migration in `WatchApp.swift` and `TVApp.swift`. |
| `sweepPadbuddyExportArchives` | Share-file preparation in the non-macOS branch of `PadDetailView+SaveCode+Focus.swift`, plus export staging tests. |
| The numeric revision overloads of `deletionWins`, `mirrorReadbackMatches`, and `retryShouldYieldToCloud` | Cloud revision and retry tests in `PadBuddyTests+PreferenceCloudSync.swift`. Shipping code uses the revision-stamp overloads. |
| `badgeWriteDecision` | The iOS notification badge writer in `DockBadge.swift`, plus badge completion tests. |
| `SectionAvailabilitySettling.shouldContinue`, `IPadQuickActionQueue.deactivate` | iOS navigation and lifecycle code in `PhoneContentView.swift` and `IPadQuickActions.swift`. |
| `HighlightedCode.embeddedHeight(for:maxHeight:)` | Snippet height tests in `PadBuddyTests+HighlightedCodeLayout.swift`. The rendered view uses the cached line-count overload. |
| `NetworkConstraintMonitor.hasResolvedPath`, `NetworkConstraintMonitor.stop` | Monitor lifecycle tests in `PadBuddyTests+NetworkConstraintMonitor.swift`. |
| `companionReadChunkBytes`, `usableDirectCompanionItems`, `CompanionItemID`, `boundedCompanionSearchInput`, `CompanionReloadOrder.invalidate`, `CompanionReloadTaskSlot` and its methods, `CompanionPageToken`, `companionReloadWithTimeout` | The companion REST importer and reload lifecycle in `CompanionPlatformPolicy.swift`, `WatchApp.swift`, and `TVApp.swift`, plus companion tests. |
| `StandaloneWindowLoadIdentity.route`, `StandaloneWindowLoadIdentity.clientIdentity` | Synthesized `Hashable` and `Equatable` implementations. Window tasks use the whole identity value. |
| The numeric revision overload of `PreferenceCloudSync.shouldAdoptCloudValue` | Preference synchronization tests. Shipping code uses revision stamps. |
| `QuestionDrafter.usableSolution`, `PadCodeExplainer.maxCodeCharacters` | Foundation Models branches in the same files, plus drafting and code explanation tests. Hosted SourceKit analysis reports these despite their references. |

Review references before adding any entry.
Remove an entry when its declaration is removed or the analyzer can resolve its references.
Do not add unused shipping code to this baseline.
