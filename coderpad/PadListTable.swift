//
//  PadListTable.swift
//  coderpad
//

import AppKit
import SwiftUI

/// One entry in a pad row's right-click menu, built by the caller and rendered as an
/// `NSMenuItem` (the hosted SwiftUI content is hit-transparent, so the menu can't be a
/// SwiftUI `.contextMenu`).
enum PadRowMenuItem {
    case button(title: String, isDestructive: Bool = false, isEnabled: Bool = true, perform: () -> Void)
    case separator
}

/// Carries a menu item's closure as an `NSMenuItem.representedObject`, so a single
/// `@objc` action can dispatch any item.
private final class MenuActionBox {
    let perform: () -> Void
    init(_ perform: @escaping () -> Void) { self.perform = perform }
}

/// An `NSTableView`-backed pad list (#439). Unlike SwiftUI `List` — which rebuilds
/// *every* row's body on each selection change and stalled large lists, and whose
/// `.equatable()` rows can't be made both lazy and click-safe — an `NSTableView`
/// materializes and recycles only the visible rows, so selection is near-instant
/// regardless of length, the way Mail's message list works.
///
/// Each row hosts the SwiftUI `PadRowHostableContent` in an `NSHostingView`. The
/// hosted content is hit-transparent except its favorite star, so left-clicks fall
/// through to the table for native selection. Selection, double-click-to-open, swipe
/// actions, keyboard nav, drag, and the right-click menu are all native table
/// behaviors driven by the closures below.
struct PadListTable: NSViewRepresentable {
    /// The rows to show, already filtered and sorted by the caller.
    var pads: [Pad]
    /// The selected pad ids, two-way bound to the owning view's `selectedIDs`.
    @Binding var selection: Set<String>
    /// A pad id to scroll into view once (e.g. a restored selection on launch).
    var scrollToID: String?
    /// Called after `scrollToID` has been honored so the caller can clear it.
    var onScrolledToID: () -> Void
    /// Disables the destructive swipe action when the account is read-only.
    var isReadOnly: Bool
    /// The SwiftUI content for a row (`PadRowHostableContent`).
    var rowContent: (Pad) -> AnyView
    /// Opens the pad in its own window on double-click.
    var onDoubleClick: (Pad) -> Void
    /// Opens the pad (browser) on Return, matching the previous `.onKeyPress(.return)`.
    var onReturn: (Pad) -> Void
    /// Whether the pad is currently a favorite, for the leading swipe's title/icon.
    var isFavorite: (Pad) -> Bool
    /// Toggles the pad's favorite state (leading swipe).
    var onToggleFavorite: (Pad) -> Void
    /// Requests deletion of the pad (trailing swipe) — opens the caller's confirmation.
    var onDelete: (Pad) -> Void
    /// The drag payload for a row: carries the pad's URL (external drops) and the
    /// internal favorite JSON (so it can be dropped on the sidebar Favorites). `nil`
    /// makes the row non-draggable. Built at the AppKit layer because the hosted
    /// SwiftUI content is hit-transparent, which disables a SwiftUI `.draggable`.
    var pasteboardItem: (Pad) -> NSPasteboardItem?
    /// The right-click menu entries for a row. The caller decides single-row vs
    /// multi-selection contents (reading its own selection). Empty → no menu.
    var menuItems: (Pad) -> [PadRowMenuItem]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = PadTableView()
        table.headerView = nil
        table.style = .inset
        table.usesAutomaticRowHeights = true
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
        let column = NSTableColumn(identifier: .padColumn)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.handleDoubleClick)
        table.onReturn = { [weak coordinator = context.coordinator] in coordinator?.handleReturn() }
        table.menuForRow = { [weak coordinator = context.coordinator] row in coordinator?.menu(forRow: row) }
        // Allow dragging rows out of the app (a pad link into Slack/Mail) and onto the
        // in-app sidebar Favorites (the internal favorite payload).
        table.setDraggingSourceOperationMask([.copy, .generic], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        context.coordinator.tableView = table
        context.coordinator.reloadIfNeeded(pads, force: true)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.tableView else { return }

        // Only reload when the row set actually changed (filter/sort/refresh) — never
        // on a bare selection change, which is the whole point of the rewrite.
        coordinator.reloadIfNeeded(pads, force: false)
        coordinator.applySelection(selection)

        if let scrollToID, let row = coordinator.index(of: scrollToID) {
            table.scrollRowToVisible(row)
            DispatchQueue.main.async { onScrolledToID() }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: PadListTable
        weak var tableView: NSTableView?
        private var pads: [Pad] = []
        private var indexByID: [String: Int] = [:]
        /// Guards against the selection binding and the table's selection ping-ponging.
        private var isApplyingSelection = false

        init(_ parent: PadListTable) {
            self.parent = parent
        }

        // MARK: Data

        func reloadIfNeeded(_ newPads: [Pad], force: Bool) {
            let changed = force || newPads.map(\.id) != pads.map(\.id)
            pads = newPads
            indexByID = Dictionary(newPads.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard changed else { return }

            tableView?.reloadData()
            // reloadData drops the selection; restore it from the binding.
            applySelection(parent.selection)
        }

        func index(of id: String) -> Int? { indexByID[id] }

        func numberOfRows(in _: NSTableView) -> Int { pads.count }

        func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            let cell = tableView.makeView(withIdentifier: .padCell, owner: self) as? PadRowCellView
                ?? PadRowCellView(identifier: .padCell)
            cell.host(parent.rowContent(pads[row]))
            return cell
        }

        func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard pads.indices.contains(row) else { return nil }

            return parent.pasteboardItem(pads[row])
        }

        // MARK: Selection

        /// Push the binding's selection into the table without echoing it back.
        func applySelection(_ ids: Set<String>) {
            guard let tableView else { return }

            let rows = IndexSet(ids.compactMap { indexByID[$0] })
            guard rows != tableView.selectedRowIndexes else { return }

            isApplyingSelection = true
            tableView.selectRowIndexes(rows, byExtendingSelection: false)
            isApplyingSelection = false
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let tableView = notification.object as? NSTableView else { return }

            let ids = Set(tableView.selectedRowIndexes.compactMap { pads.indices.contains($0) ? pads[$0].id : nil })
            if ids != parent.selection { parent.selection = ids }
        }

        // MARK: Actions

        @objc func handleDoubleClick() {
            guard let tableView, tableView.clickedRow >= 0, pads.indices.contains(tableView.clickedRow) else { return }

            parent.onDoubleClick(pads[tableView.clickedRow])
        }

        func handleReturn() {
            guard let tableView, let row = tableView.selectedRowIndexes.first, pads.indices.contains(row) else { return }

            parent.onReturn(pads[row])
        }

        // MARK: Swipe actions

        func tableView(_: NSTableView, rowActionsForRow row: Int,
                       edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard pads.indices.contains(row) else { return [] }

            let pad = pads[row]
            switch edge {
            case .leading:
                let starred = parent.isFavorite(pad)
                let action = NSTableViewRowAction(
                    style: .regular,
                    title: starred ? String(localized: "Unfavorite") : String(localized: "Favorite")
                ) { [weak self] _, _ in
                    self?.parent.onToggleFavorite(pad)
                    self?.tableView?.rowActionsVisible = false
                }
                action.backgroundColor = .systemYellow
                return [action]
            case .trailing:
                guard !parent.isReadOnly else { return [] }

                let action = NSTableViewRowAction(
                    style: .destructive,
                    title: String(localized: "Delete")
                ) { [weak self] _, _ in
                    self?.parent.onDelete(pad)
                    self?.tableView?.rowActionsVisible = false
                }
                return [action]
            @unknown default:
                return []
            }
        }

        // MARK: Context menu

        func menu(forRow row: Int) -> NSMenu? {
            guard pads.indices.contains(row) else { return nil }

            let items = parent.menuItems(pads[row])
            guard !items.isEmpty else { return nil }

            let menu = NSMenu()
            menu.autoenablesItems = false
            for item in items {
                switch item {
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
            return menu
        }

        @objc private func runMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? MenuActionBox)?.perform()
        }
    }
}

/// `NSTableView` subclass: forwards Return/Enter to a handler (open the selected pad),
/// and builds the per-row right-click menu. Arrow keys keep the table's native
/// row-to-row navigation.
private final class PadTableView: NSTableView {
    var onReturn: (() -> Void)?
    var menuForRow: ((Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = keypad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }

        return menuForRow?(row)
    }
}

/// A table cell that hosts a row's SwiftUI content in an `NSHostingView`, sized to the
/// content's intrinsic height so `usesAutomaticRowHeights` lays the row out correctly.
private final class PadRowCellView: NSTableCellView {
    private var hosting: NSHostingView<AnyView>?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

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
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        hosting = hostingView
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let padCell = NSUserInterfaceItemIdentifier("PadRowCellView")
    static let padColumn = NSUserInterfaceItemIdentifier("PadColumn")
}
