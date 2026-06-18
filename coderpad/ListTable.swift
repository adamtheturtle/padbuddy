//
//  ListTable.swift
//  coderpad
//

import AppKit
import SwiftUI

/// One entry in a row's right-click menu, built by the caller and rendered as an
/// `NSMenuItem` (the hosted SwiftUI content is hit-transparent, so the menu can't be a
/// SwiftUI `.contextMenu`).
enum RowMenuItem {
    case button(title: String, isDestructive: Bool = false, isEnabled: Bool = true, perform: () -> Void)
    case separator
}

/// One swipe action on a row edge, rendered as an `NSTableViewRowAction`.
struct RowSwipeAction {
    var title: String
    var isDestructive: Bool = false
    /// Background colour for the revealed button (e.g. yellow for favorite). `nil`
    /// uses the system default (grey for regular, red for destructive).
    var tint: NSColor?
    var perform: () -> Void
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
struct ListTable<Item: Identifiable>: NSViewRepresentable where Item.ID: Hashable {
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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
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
        return scroll
    }

    func updateNSView(_: NSScrollView, context: Context) {
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

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
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

        func numberOfRows(in _: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            let cell = tableView.makeView(withIdentifier: .listCell, owner: self) as? HostingCellView
                ?? HostingCellView(identifier: .listCell)
            cell.host(parent.rowContent(items[row]))
            return cell
        }

        func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard items.indices.contains(row) else { return nil }

            return parent.pasteboardItem(items[row])
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

        func tableViewSelectionDidChange(_ notification: Notification) {
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

        // MARK: Swipe actions

        func tableView(_: NSTableView, rowActionsForRow row: Int,
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
        func menuNeedsUpdate(_ menu: NSMenu) {
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

/// `NSTableView` subclass: forwards Return/Enter to a handler (open the selected row).
/// The per-row right-click menu is the table's own `menu` property, populated lazily by
/// the coordinator's `menuNeedsUpdate(_:)` — see #450. Arrow keys keep the table's
/// native row-to-row navigation.
private final class KeyHandlingTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = keypad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Only show the menu — and let AppKit run its native right-clicked-row
        // highlight (#450) — when the click lands on a row, not the empty area below
        // the list. `super` sets `clickedRow`, draws the outline, and returns `menu`,
        // whose items the coordinator fills in via `menuNeedsUpdate(_:)`.
        let point = convert(event.locationInWindow, from: nil)
        guard row(at: point) >= 0 else { return nil }

        return super.menu(for: event)
    }
}

/// A table cell that hosts a row's SwiftUI content in an `NSHostingView`, sized to the
/// content's intrinsic height so `usesAutomaticRowHeights` lays the row out correctly.
private final class HostingCellView: NSTableCellView {
    private var hosting: NSHostingView<AnyView>?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func host(_ view: AnyView) {
        if let hosting {
            hosting.rootView = view
            return
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = .intrinsicContentSize
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        hosting = hostingView
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let listCell = NSUserInterfaceItemIdentifier("ListTableHostingCell")
    static let listColumn = NSUserInterfaceItemIdentifier("ListTableColumn")
}
