//
//  MacQuestionTable+Views.swift
//  coderpad
//
//  Split from MacQuestionTable.swift to keep it within the lint length limit:
//  the AppKit table/cell views and their helpers moved here.
//

#if os(macOS)
import AppKit
import SwiftUI

final class MacQuestionTableView: NSTableView {
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

final class MacQuestionCellView: NSTableCellView {
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
        buildStarButton()

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

        let starTrailingInset = FastListRowMetrics.dateColumnWidth + 32
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
            starButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -starTrailingInset),
            starButton.widthAnchor.constraint(equalToConstant: 18),
            starButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func buildStarButton() {
        starButton.isBordered = false
        starButton.imagePosition = .imageOnly
        starButton.imageScaling = .scaleProportionallyDown
        starButton.target = self
        starButton.action = #selector(toggleFavorite)
        starButton.translatesAutoresizingMaskIntoConstraints = false
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

    func updateHoverStateFromMouseLocation() {
        isHovering = containsMouse
    }

    private func updateStarAppearance() {
        let description = isFavorite ? "Remove from Favorites" : "Add to Favorites"
        let symbolName = isFavorite ? "star.fill" : "star"
        let starImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        let configuration = NSImage.SymbolConfiguration(pointSize: NSFont.smallSystemFontSize, weight: .regular)
        starButton.image = starImage?.withSymbolConfiguration(configuration)
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

final class MacQuestionMenuAction {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}

extension NSUserInterfaceItemIdentifier {
    static let macQuestionCell = NSUserInterfaceItemIdentifier("MacQuestionCell")
    static let macQuestionColumn = NSUserInterfaceItemIdentifier("MacQuestionColumn")
}
#endif
