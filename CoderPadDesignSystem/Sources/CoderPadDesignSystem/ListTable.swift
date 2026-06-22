//
//  ListTable.swift
//  CoderPadDesignSystem
//
//  An NSTableView-backed list, lifted out of the app (#515/#439) so both apps share
//  it. The app-specific favorite-drag coupling (`UTType.coderpadFavorite` /
//  `FavoriteDragMonitor`) is replaced by injected `onDragSessionBegan` /
//  `onDragSessionEnded` hooks, so the host inspects the dragging session itself and
//  the design-system table stays free of any domain pasteboard types.
//

import AppKit
import SwiftUI

/// One entry in a row's right-click menu, built by the caller and rendered as an
/// `NSMenuItem` (the hosted SwiftUI content is hit-transparent, so the menu can't be a
/// SwiftUI `.contextMenu`).
public enum RowMenuItem {
    case button(title: String, isDestructive: Bool = false, isEnabled: Bool = true, perform: () -> Void)
    case separator
}

/// One swipe action on a row edge, rendered as an `NSTableViewRowAction`.
public struct RowSwipeAction {
    var title: String
    var isDestructive: Bool
    /// Background colour for the revealed button (e.g. yellow for favorite). `nil`
    /// uses the system default (grey for regular, red for destructive).
    var tint: NSColor?
    /// An SF Symbol shown on the revealed button instead of the title (#454), the
    /// standard macOS swipe look (Finder/Mail). `nil` falls back to the text title.
    /// `title` is still set so VoiceOver announces the action. (NSTableViewRowAction
    /// renders an image *or* a title, never both — true icon-over-text isn't
    /// expressible with the native API.)
    var systemImage: String?
    var perform: () -> Void

    public init(
        title: String,
        isDestructive: Bool = false,
        tint: NSColor? = nil,
        systemImage: String? = nil,
        perform: @escaping () -> Void
    ) {
        self.title = title
        self.isDestructive = isDestructive
        self.tint = tint
        self.systemImage = systemImage
        self.perform = perform
    }
}

/// Carries a menu item's closure as an `NSMenuItem.representedObject`, so a single
/// `@objc` action can dispatch any item.
private final class MenuActionBox {
    let perform: () -> Void
    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }
}

/// An `NSTableView`-backed list (#439). Unlike SwiftUI `List` — which rebuilds *every*
/// row's body on each selection change and stalled large lists, and whose
/// `.equatable()` rows can't be made both lazy and click-safe — an `NSTableView`
/// materializes and recycles only the visible rows, so selection is near-instant
/// regardless of length, the way Mail's message list works.
///
/// Each row hosts a SwiftUI view in an `NSHostingView`. The hosted content must be
/// hit-transparent except its interactive controls (e.g. a favorite star) — apply
/// `.allowsHitTesting(false)` to the non-interactive parts — so left-clicks fall
/// through to the table for native selection. Selection, double-click, swipe, keyboard
/// nav, drag, and the right-click menu are native table behaviors driven by closures.
public struct ListTable<Item: Identifiable>: NSViewRepresentable where Item.ID: Hashable {
    /// The rows to show, already filtered and sorted by the caller.
    var items: [Item]
    /// The selected ids, two-way bound to the owning view's selection set.
    @Binding var selection: Set<Item.ID>
    /// An id to scroll into view once (e.g. a restored selection on launch).
    var scrollToID: Item.ID?
    /// Called after `scrollToID` has been honored so the caller can clear it.
    var onScrolledToID: () -> Void
    /// The SwiftUI content for a row (hit-transparent except its controls).
    var rowContent: (Item) -> AnyView
    /// Opens the item on double-click.
    var onDoubleClick: (Item) -> Void
    /// Opens the item on Return, matching the previous `.onKeyPress(.return)`.
    var onReturn: (Item) -> Void
    /// Leading-edge swipe actions (e.g. favorite). Empty → no leading swipe.
    var leadingActions: (Item) -> [RowSwipeAction]
    /// Trailing-edge swipe actions (e.g. delete). Empty → no trailing swipe.
    var trailingActions: (Item) -> [RowSwipeAction]
    /// The drag payload for a row, or `nil` to make it non-draggable. Built at the
    /// AppKit layer because the hosted SwiftUI content is hit-transparent, which
    /// disables a SwiftUI `.draggable`.
    var pasteboardItem: (Item) -> NSPasteboardItem?
    /// The right-click menu entries for a row. The caller decides single-row vs
    /// multi-selection contents (reading its own selection). Empty → no menu.
    var menuItems: (Item) -> [RowMenuItem]
    /// Reports the id of the row at the top of the viewport when the user finishes a
    /// scroll, so the caller can persist and restore the free-scroll position across
    /// launches (#273). `nil` when the list is empty.
    var onTopRowChange: ((Item.ID?) -> Void)?
    /// Called when a row drag begins, with the dragging session, so the host can react
    /// to an in-flight drag (e.g. reveal a sidebar drop zone when the session carries a
    /// favorite payload, #444). The host inspects the session, keeping app pasteboard
    /// types out of the design system. Default: no-op.
    var onDragSessionBegan: (NSDraggingSession) -> Void
    /// Called when a row drag ends (drop or cancel). Default: no-op.
    var onDragSessionEnded: () -> Void

    public init(
        items: [Item],
        selection: Binding<Set<Item.ID>>,
        scrollToID: Item.ID? = nil,
        onScrolledToID: @escaping () -> Void,
        rowContent: @escaping (Item) -> AnyView,
        onDoubleClick: @escaping (Item) -> Void,
        onReturn: @escaping (Item) -> Void,
        leadingActions: @escaping (Item) -> [RowSwipeAction],
        trailingActions: @escaping (Item) -> [RowSwipeAction],
        pasteboardItem: @escaping (Item) -> NSPasteboardItem?,
        menuItems: @escaping (Item) -> [RowMenuItem],
        onTopRowChange: ((Item.ID?) -> Void)? = nil,
        onDragSessionBegan: @escaping (NSDraggingSession) -> Void = { _ in },
        onDragSessionEnded: @escaping () -> Void = {}
    ) {
        self.items = items
        _selection = selection
        self.scrollToID = scrollToID
        self.onScrolledToID = onScrolledToID
        self.rowContent = rowContent
        self.onDoubleClick = onDoubleClick
        self.onReturn = onReturn
        self.leadingActions = leadingActions
        self.trailingActions = trailingActions
        self.pasteboardItem = pasteboardItem
        self.menuItems = menuItems
        self.onTopRowChange = onTopRowChange
        self.onDragSessionBegan = onDragSessionBegan
        self.onDragSessionEnded = onDragSessionEnded
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let table = KeyHandlingTableView()
        table.headerView = nil
        table.style = .inset
        table.usesAutomaticRowHeights = true
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
        let column = NSTableColumn(identifier: .listColumn)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.handleDoubleClick)
        table.onReturn = { [weak coordinator = context.coordinator] in coordinator?.handleReturn() }
        // Drive the right-click menu through the table's own `menu` property (populated
        // lazily in `menuNeedsUpdate`) rather than overriding `menu(for:)`. That lets
        // NSTableView's native contextual-menu machinery run, which draws the focus-ring
        // outline around a right-clicked row that isn't selected (#450).
        let rowMenu = NSMenu()
        rowMenu.delegate = context.coordinator
        table.menu = rowMenu
        // Allow dragging rows out of the app (a link into Slack/Mail) and onto the
        // in-app sidebar Favorites (the internal favorite payload).
        table.setDraggingSourceOperationMask([.copy, .generic], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        context.coordinator.tableView = table
        context.coordinator.reloadIfNeeded(items, force: true)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // Report the top visible row when a user scroll settles, so the caller can
        // persist/restore the free-scroll position (#273). didEndLiveScroll fires once
        // per gesture — far cheaper than streaming every bounds change. The selector
        // observer auto-unregisters when the coordinator deallocates (macOS 10.11+).
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.liveScrollEnded),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scroll
        )
        return scroll
    }

    public func updateNSView(_: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.tableView else { return }

        // Only reload when the row set actually changed (filter/sort/refresh) — never
        // on a bare selection change, which is the whole point of the rewrite.
        coordinator.reloadIfNeeded(items, force: false)
        coordinator.applySelection(selection)

        if let scrollToID, let row = coordinator.index(of: scrollToID) {
            table.scrollRowToVisible(row)
            DispatchQueue.main.async { onScrolledToID() }
        }
    }

    @preconcurrency @MainActor
    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: ListTable
        weak var tableView: NSTableView?
        private var items: [Item] = []
        private var indexByID: [Item.ID: Int] = [:]
        /// Guards against the selection binding and the table's selection ping-ponging.
        private var isApplyingSelection = false

        init(_ parent: ListTable) {
            self.parent = parent
        }

        /// Xcode 26.5's SIL optimizer (EarlyPerfInliner) crashes while optimizing this
        /// generic Coordinator's destructor in the Release build (local Xcode 27 is
        /// unaffected). An explicit, optimization-opted-out deinit sidesteps the compiler
        /// bug; the member-wise teardown it would otherwise synthesize is unchanged.
        @_optimize(none)
        deinit {}

        // MARK: Data

        func reloadIfNeeded(_ newItems: [Item], force: Bool) {
            let changed = force || newItems.map(\.id) != items.map(\.id)
            items = newItems
            indexByID = Dictionary(newItems.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard changed else { return }

            tableView?.reloadData()
            // reloadData drops the selection; restore it from the binding.
            applySelection(parent.selection)
        }

        func index(of id: Item.ID) -> Int? {
            indexByID[id]
        }

        public func numberOfRows(in _: NSTableView) -> Int {
            items.count
        }

        public func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            let cell = tableView.makeView(withIdentifier: .listCell, owner: self) as? HostingCellView
                ?? HostingCellView(identifier: .listCell)
            cell.host(parent.rowContent(items[row]))
            return cell
        }

        public func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard items.indices.contains(row) else { return nil }

            return parent.pasteboardItem(items[row])
        }

        /// Forward the drag's start to the host so it can react to an in-flight drag
        /// (e.g. reveal the sidebar's empty-state favorite drop zone, #444). The host
        /// inspects the session's pasteboard for its own payload types.
        public func tableView(_: NSTableView, draggingSession session: NSDraggingSession,
                              willBeginAt _: NSPoint, forRowIndexes _: IndexSet) {
            parent.onDragSessionBegan(session)
        }

        /// Drop or cancel — let the host collapse anything it revealed (#444).
        public func tableView(_: NSTableView, draggingSession _: NSDraggingSession,
                              endedAt _: NSPoint, operation _: NSDragOperation) {
            parent.onDragSessionEnded()
        }

        // MARK: Selection

        /// Push the binding's selection into the table without echoing it back.
        func applySelection(_ ids: Set<Item.ID>) {
            guard let tableView else { return }

            let rows = IndexSet(ids.compactMap { indexByID[$0] })
            guard rows != tableView.selectedRowIndexes else { return }

            isApplyingSelection = true
            tableView.selectRowIndexes(rows, byExtendingSelection: false)
            isApplyingSelection = false
        }

        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let tableView = notification.object as? NSTableView else { return }

            let ids = Set(tableView.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].id : nil })
            if ids != parent.selection { parent.selection = ids }
        }

        // MARK: Actions

        @objc func handleDoubleClick() {
            guard let tableView, tableView.clickedRow >= 0, items.indices.contains(tableView.clickedRow) else { return }

            parent.onDoubleClick(items[tableView.clickedRow])
        }

        func handleReturn() {
            guard let tableView, let row = tableView.selectedRowIndexes.first,
                  items.indices.contains(row) else { return }

            parent.onReturn(items[row])
        }

        /// A user scroll settled — report the id of the row now at the top of the
        /// viewport so the caller can remember the scroll position (#273).
        @objc func liveScrollEnded() {
            guard parent.onTopRowChange != nil, let tableView else { return }

            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0, items.indices.contains(visible.location) else { return }

            parent.onTopRowChange?(items[visible.location].id)
        }

        // MARK: Swipe actions

        public func tableView(_: NSTableView, rowActionsForRow row: Int,
                              edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard items.indices.contains(row) else { return [] }

            let item = items[row]
            let actions = edge == .leading ? parent.leadingActions(item) : parent.trailingActions(item)
            return actions.map { action in
                let rowAction = NSTableViewRowAction(
                    style: action.isDestructive ? .destructive : .regular,
                    title: action.title
                ) { [weak self] _, _ in
                    action.perform()
                    self?.tableView?.rowActionsVisible = false
                }
                if let tint = action.tint { rowAction.backgroundColor = tint }
                // An image replaces the title on the revealed button (Apple's docs); the
                // title stays set above so VoiceOver still announces the action (#454).
                if let symbol = action.systemImage {
                    rowAction.image = NSImage(systemSymbolName: symbol, accessibilityDescription: action.title)
                }
                return rowAction
            }
        }

        // MARK: Context menu

        /// Populate the table's persistent context menu for the row the user
        /// right-clicked. Driving the menu through NSTableView's own `menu` property
        /// plus this delegate — rather than overriding `menu(for:)` to return a fresh
        /// menu — lets AppKit's native contextual-menu machinery run, which draws the
        /// focus-ring outline around a right-clicked row that isn't selected (#450).
        /// `clickedRow` is set by NSTableView before the menu opens.
        public func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let row = tableView?.clickedRow ?? -1
            guard items.indices.contains(row) else { return }

            menu.autoenablesItems = false
            for entry in parent.menuItems(items[row]) {
                switch entry {
                case .separator:
                    menu.addItem(.separator())
                case let .button(title, _, isEnabled, perform):
                    let menuItem = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.isEnabled = isEnabled
                    menuItem.representedObject = MenuActionBox(perform)
                    menu.addItem(menuItem)
                }
            }
        }

        @objc private func runMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? MenuActionBox)?.perform()
        }
    }
}
