//
//  MacQuestionTable+Behavior.swift
//  coderpad
//

#if os(macOS)
    import AppKit

    extension MacQuestionTable {
        static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
            NotificationCenter.default.removeObserver(coordinator)
            coordinator.endDragIfNeeded()
            coordinator.tableView = nil
        }
    }

    extension MacQuestionTable.Coordinator {
        func index(of id: Item.ID) -> Int? {
            indexByID[id]
        }

        func endDragIfNeeded() {
            guard dragSessionIsActive else { return }

            dragSessionIsActive = false
            parent.onDragSessionEnded()
        }

        func resetScrollRequest() {
            scrollRequest.reset()
        }

        func consumeScrollRequest(_ id: Item.ID) -> Bool {
            scrollRequest.consume(id)
        }
    }
#endif
