//
//  MacQuestionTable.swift
//  coderpad
//

#if os(macOS)
import AppKit
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

        init(_ parent: MacQuestionTable) {
            self.parent = parent
        }

        @_optimize(none)
        deinit {}

        func reloadIfNeeded(_ newItems: [Item], reloadID newReloadID: AnyHashable?, force: Bool) {
            let changed = force || newItems.map(\.id) != items.map(\.id) || newReloadID != reloadID
            items = newItems
            reloadID = newReloadID
            indexByID = Dictionary(newItems.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard changed else { return }

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
                    self.parent.toggleFavorite(item)
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

            let ids = Set(tableView.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].id : nil })
            if ids != parent.selection { parent.selection = ids }
        }

        @objc func handleDoubleClick() {
            guard let tableView, tableView.clickedRow >= 0, items.indices.contains(tableView.clickedRow) else { return }
            parent.onDoubleClick(items[tableView.clickedRow])
        }

        func handleReturn() {
            guard let tableView, let row = tableView.selectedRowIndexes.first, items.indices.contains(row) else { return }
            parent.onReturn(items[row])
        }

        @objc func liveScrollEnded() {
            guard let tableView else { return }

            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0, items.indices.contains(visible.location) else { return }
            parent.onTopRowChange(items[visible.location].id)
        }

        func tableView(_: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
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

private final class MacQuestionTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard row(at: point) >= 0 else { return nil }
        return super.menu(for: event)
    }
}

private final class MacQuestionCellView: NSTableCellView {
    private let railView = NSView()
    private let leadingGutterView = NSView()
    private let titleField = NSTextField(labelWithString: "")
    private let metadataField = NSTextField(labelWithString: "")
    private let starButton = NSButton()
    private var railWidthConstraint: NSLayoutConstraint?
    private var textLeadingConstraint: NSLayoutConstraint?
    private var trackingArea: NSTrackingArea?
    private var isFavorite = false
    private var isHovering = false {
        didSet { updateStarAppearance() }
    }
    private var onToggleFavorite: (() -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        buildView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func configure(
        presentation: QuestionRowPresentation,
        account: RowAccount?,
        isFavorite: Bool,
        onToggleFavorite: @escaping () -> Void
    ) {
        titleField.stringValue = presentation.title
        metadataField.stringValue = metadataText(presentation: presentation, account: account)
        self.onToggleFavorite = onToggleFavorite
        self.isFavorite = isFavorite
        isHovering = containsMouse

        let showsAccountRail = account != nil
        railView.isHidden = !showsAccountRail
        railWidthConstraint?.constant = showsAccountRail ? 4 : 0
        textLeadingConstraint?.constant = 10
        railView.layer?.backgroundColor = account.map { NSColor($0.tint).withAlphaComponent(0.75).cgColor }
        updateStarAppearance()
        setAccessibilityLabel(presentation.accessibilityLabel)
    }

    private func buildView() {
        wantsLayer = true
        railView.wantsLayer = true
        railView.layer?.cornerRadius = 2
        railView.translatesAutoresizingMaskIntoConstraints = false
        leadingGutterView.translatesAutoresizingMaskIntoConstraints = false

        titleField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        titleField.textColor = .labelColor
        metadataField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        metadataField.textColor = .secondaryLabelColor
        for field in [titleField, metadataField] {
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.translatesAutoresizingMaskIntoConstraints = false
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        starButton.isBordered = false
        starButton.imagePosition = .imageOnly
        starButton.imageScaling = .scaleProportionallyDown
        starButton.target = self
        starButton.action = #selector(toggleFavorite)
        starButton.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleField, metadataField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [railView, leadingGutterView, textStack, starButton] {
            addSubview(view)
        }

        let railWidth = railView.widthAnchor.constraint(equalToConstant: 0)
        let textLeading = textStack.leadingAnchor.constraint(equalTo: leadingGutterView.trailingAnchor, constant: 10)
        railWidthConstraint = railWidth
        textLeadingConstraint = textLeading

        NSLayoutConstraint.activate([
            railView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            railView.centerYAnchor.constraint(equalTo: centerYAnchor),
            railWidth,
            railView.heightAnchor.constraint(equalToConstant: 36),

            leadingGutterView.leadingAnchor.constraint(equalTo: railView.trailingAnchor),
            leadingGutterView.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingGutterView.widthAnchor.constraint(equalToConstant: 8),
            leadingGutterView.heightAnchor.constraint(equalToConstant: 8),

            textLeading,
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: starButton.leadingAnchor, constant: -8),

            starButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            starButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(FastListRowMetrics.dateColumnWidth + 32)),
            starButton.widthAnchor.constraint(equalToConstant: 18),
            starButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with _: NSEvent) {
        isHovering = false
    }

    private func updateStarAppearance() {
        let description = isFavorite ? "Remove from Favorites" : "Add to Favorites"
        let starImage = NSImage(systemSymbolName: isFavorite ? "star.fill" : "star", accessibilityDescription: description)
        starButton.image = starImage?.withSymbolConfiguration(.init(pointSize: NSFont.smallSystemFontSize, weight: .regular))
        starButton.contentTintColor = isFavorite ? .systemYellow : .secondaryLabelColor
        starButton.alphaValue = isFavorite || isHovering ? 1 : 0
        starButton.toolTip = description
    }

    private var containsMouse: Bool {
        guard let window else { return false }

        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point)
    }

    private func metadataText(presentation: QuestionRowPresentation, account: RowAccount?) -> String {
        var parts: [String] = []
        if let account { parts.append(account.name) }
        if let language = presentation.languageDisplayName { parts.append(language) }
        if presentation.interviewType == .takeHome { parts.append(InterviewType.takeHome.label) }
        if presentation.isDraft { parts.append(String(localized: "Draft")) }
        return parts.joined(separator: " · ")
    }

    @objc private func toggleFavorite() {
        onToggleFavorite?()
    }
}

private final class MacQuestionMenuAction {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let macQuestionCell = NSUserInterfaceItemIdentifier("MacQuestionCell")
    static let macQuestionColumn = NSUserInterfaceItemIdentifier("MacQuestionColumn")
}
#endif
