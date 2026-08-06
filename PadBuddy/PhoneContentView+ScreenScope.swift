//
//  PhoneContentView+ScreenScope.swift
//  coderpad
//

#if os(iOS)
    import Foundation

    extension PhoneContentView {
        var screenSelectionAccountID: UUID? {
            store.isMergedView ? mergedRouting.selectedScreenAccountID : store.currentAccountID
        }
    }
#endif
