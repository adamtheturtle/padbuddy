//
//  MacQuestionTable.swift
//  coderpad
//

#if os(macOS)
    import AppKit
    import FastList
    import SwiftUI

    /// Native AppKit renderer for the macOS Questions lists. The generic `FastList` path
    /// hosts SwiftUI rows in recycled `NSHostingView`s; question rows are busy enough that
    /// hosting churn shows up during fast scrolls. This table keeps the same list behaviors
    /// but renders each visible row with plain AppKit controls.
    struct MacQuestionTable<Item: Identifiable>: NSViewRepresentable where Item.ID: Hashable {
        let items: [Item]
        @Binding var selection: Set<Item.ID>
        var reloadID: AnyHashable?
        var scrollToID: Item.ID?
        var onScrolledToID: () -> Void
        var presentation: (Item) -> QuestionRowPresentation
        var rowAccount: (Item) -> RowAccount?
        var isFavorite: (Item) -> Bool
        var toggleFavorite: (Item) -> Void
        var onDoubleClick: (Item) -> Void
        var onReturn: (Item) -> Void
        var leadingActions: (Item) -> [SwipeAction]
        var trailingActions: (Item) -> [SwipeAction]
        var pasteboardItem: (Item) -> NSPasteboardItem?
        var menuItems: (Item) -> [MenuItem]
        var onTopRowChange: (Item.ID?) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let table = MacQuestionTableView()
            table.headerView = nil
            table.style = .inset
            table.rowHeight = FastListRowMetrics.macHeight
            table.usesAutomaticRowHeights = false
            table.allowsMultipleSelection = true
            table.allowsEmptySelection = true
            table.selectionHighlightStyle = .regular
            table.backgroundColor = .clear

            let column = NSTableColumn(identifier: .macQuestionColumn)
            column.resizingMask = .autoresizingMask
            table.addTableColumn(column)
            table.dataSource = context.coordinator
            table.delegate = context.coordinator
            table.target = context.coordinator
            table.doubleAction = #selector(Coordinator.handleDoubleClick)
            table.onReturn = { [weak coordinator = context.coordinator] in coordinator?.handleReturn() }

            let rowMenu = NSMenu()
            rowMenu.delegate = context.coordinator
            table.menu = rowMenu

            table.setDraggingSourceOperationMask([.copy, .generic], forLocal: true)
            table.setDraggingSourceOperationMask(.copy, forLocal: false)

            context.coordinator.tableView = table
            context.coordinator.reloadIfNeeded(items, reloadID: reloadID, force: true)

            let scroll = NSScrollView()
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.visibleBoundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: scroll.contentView
            )
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.liveScrollChanged),
                name: NSScrollView.didLiveScrollNotification,
                object: scroll
            )
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.liveScrollEnded),
                name: NSScrollView.didEndLiveScrollNotification,
                object: scroll
            )
            return scroll
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            let coordinator = context.coordinator
            coordinator.parent = self
            guard let table = coordinator.tableView else { return }

            coordinator.reloadIfNeeded(items, reloadID: reloadID, force: false)
            coordinator.applySelection(selection)

            if let scrollToID, let row = coordinator.index(of: scrollToID) {
                table.scrollRowToVisible(row)
                DispatchQueue.main.async { onScrolledToID() }
            }
            scrollView.hasVerticalScroller = true
        }

        @MainActor
        final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
            var parent: MacQuestionTable
            weak var tableView: NSTableView?
            private var items: [Item] = []
            private var indexByID: [Item.ID: Int] = [:]
            private var reloadID: AnyHashable?
            private var isApplyingSelection = false
            private var topRowReportTask: Task<Void, Never>?
            private var lastReportedTopRow: Item.ID?

            init(_ parent: MacQuestionTable) {
                self.parent = parent
            }

            @_optimize(none)
            deinit { topRowReportTask?.cancel() }

            func reloadIfNeeded(_ newItems: [Item], reloadID newReloadID: AnyHashable?, force: Bool) {
                // Filtering changes the rows without touching `reloadID`, so the ids
                // still have to be compared — but in place: mapping both sides to
                // `[Item.ID]` allocated two arrays on every update pass, and this runs
                // for every selection change, hover, and unrelated SwiftUI update (#2081).
                let idsChanged = newItems.count != items.count
                    || !newItems.elementsEqual(items) { $0.id == $1.id }
                let changed = force || idsChanged || newReloadID != reloadID
                items = newItems
                reloadID = newReloadID
                guard changed else { return }

                // Row indices only move when the id list does, so the dictionary is
                // rebuilt here rather than on every pass (#2081).
                if idsChanged || force {
                    indexByID = Dictionary(newItems.enumerated().map { ($1.id, $0) },
                                           uniquingKeysWith: { first, _ in first })
                }
                tableView?.reloadData()
                applySelection(parent.selection)
            }

            func index(of id: Item.ID) -> Int? {
                indexByID[id]
            }

            func numberOfRows(in _: NSTableView) -> Int {
                items.count
            }

            func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
                guard items.indices.contains(row) else { return nil }

                let item = items[row]
                let cell = tableView.makeView(withIdentifier: .macQuestionCell, owner: self) as? MacQuestionCellView
                    ?? MacQuestionCellView(identifier: .macQuestionCell)
                cell.configure(
                    presentation: parent.presentation(item),
                    account: parent.rowAccount(item),
                    isFavorite: parent.isFavorite(item),
                    onToggleFavorite: { [weak self] in
                        guard let self else { return }

                        parent.toggleFavorite(item)
                    }
                )
                return cell
            }

            func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
                guard items.indices.contains(row) else { return nil }

                return parent.pasteboardItem(items[row])
            }

            func applySelection(_ ids: Set<Item.ID>) {
                guard let tableView else { return }

                let rows = IndexSet(ids.compactMap { indexByID[$0] })
                guard rows != tableView.selectedRowIndexes else { return }

                isApplyingSelection = true
                tableView.selectRowIndexes(rows, byExtendingSelection: false)
                isApplyingSelection = false
            }

            func tableViewSelectionDidChange(_ notification: Notification) {
                guard !isApplyingSelection, let tableView = notification.object as? NSTableView else { return }

                let ids = Set(tableView.selectedRowIndexes
                    .compactMap { items.indices.contains($0) ? items[$0].id : nil })
                if ids != parent.selection { parent.selection = ids }
            }

            @objc func handleDoubleClick() {
                guard let tableView, tableView.clickedRow >= 0,
                      items.indices.contains(tableView.clickedRow) else { return }

                parent.onDoubleClick(items[tableView.clickedRow])
            }

            func handleReturn() {
                guard let tableView, let row = tableView.selectedRowIndexes.first,
                      items.indices.contains(row) else { return }

                parent.onReturn(items[row])
            }

            @objc func liveScrollChanged() {
                syncVisibleHoverStates()
            }

            @objc func liveScrollEnded() {
                syncVisibleHoverStates()
                reportTopRow()
            }

            /// Bounds notifications cover wheel, keyboard, accessibility, and
            /// programmatic scrolling, not only AppKit's live-scroll gesture pair.
            /// Coalesce them because a single scroll produces many bounds updates.
            @objc func visibleBoundsChanged() {
                syncVisibleHoverStates()
                topRowReportTask?.cancel()
                topRowReportTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }

                    self?.reportTopRow()
                }
            }

            private func reportTopRow() {
                guard let tableView else { return }

                let visible = tableView.rows(in: tableView.visibleRect)
                guard visible.length > 0, items.indices.contains(visible.location) else { return }

                let id = items[visible.location].id
                guard id != lastReportedTopRow else { return }

                lastReportedTopRow = id
                parent.onTopRowChange(id)
            }

            private func syncVisibleHoverStates() {
                guard let tableView else { return }

                let visibleRows = tableView.rows(in: tableView.visibleRect)
                for row in visibleRows.location ..< NSMaxRange(visibleRows) {
                    let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? MacQuestionCellView
                    cell?.updateHoverStateFromMouseLocation()
                }
            }

            func tableView(
                _: NSTableView,
                rowActionsForRow row: Int,
                edge: NSTableView.RowActionEdge
            ) -> [NSTableViewRowAction] {
                guard items.indices.contains(row) else { return [] }

                let item = items[row]
                let actions = edge == .leading ? parent.leadingActions(item) : parent.trailingActions(item)
                return actions.map { action in
                    let rowAction = NSTableViewRowAction(
                        style: action.role == .destructive ? .destructive : .regular,
                        title: action.title
                    ) { [weak self] _, _ in
                        action.action()
                        self?.tableView?.rowActionsVisible = false
                    }
                    if let tint = action.tint { rowAction.backgroundColor = NSColor(tint) }
                    if let symbol = action.systemImage {
                        rowAction.image = NSImage(systemSymbolName: symbol, accessibilityDescription: action.title)
                    }
                    return rowAction
                }
            }

            func menuNeedsUpdate(_ menu: NSMenu) {
                menu.removeAllItems()
                let row = tableView?.clickedRow ?? -1
                guard items.indices.contains(row) else { return }

                menu.autoenablesItems = false
                for entry in parent.menuItems(items[row]) {
                    switch entry {
                    case .separator:
                        menu.addItem(.separator())
                    case let .button(title, isEnabled, _, action):
                        let item = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
                        item.target = self
                        item.isEnabled = isEnabled
                        item.representedObject = MacQuestionMenuAction(action)
                        menu.addItem(item)
                    }
                }
            }

            @objc private func runMenuAction(_ sender: NSMenuItem) {
                (sender.representedObject as? MacQuestionMenuAction)?.action()
            }
        }
    }
#endif
