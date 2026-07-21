//
//  AttributedDocumentPrinter.swift
//  coderpad
//

import CoreText
import PDFKit
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Renders a SwiftUI document with a source footer on every PDF page, then opens
/// the platform print UI. Page-level attribution survives printed excerpts where
/// the document's title page is not included.
@MainActor
func printAttributedDocument(
    _ content: some View,
    jobTitle: String,
    sourceURL: URL,
    margins: CGFloat = 36
) {
    let pageSize = attributedPrintPageSize()
    guard let data = attributedPDFData(content, pageSize: pageSize, margins: margins,
                                       sourceURL: sourceURL) else { return }

    presentAttributedPrintPanel(data: data, pageSize: pageSize, jobTitle: jobTitle)
}

@MainActor
private func attributedPDFData(
    _ content: some View,
    pageSize: CGSize,
    margins: CGFloat,
    sourceURL: URL
) -> Data? {
    let footerHeight: CGFloat = 18
    let contentWidth = pageSize.width - margins * 2
    let printableHeight = pageSize.height - margins * 2 - footerHeight
    guard contentWidth > 0, printableHeight > 0 else { return nil }

    let document = content
        .frame(width: contentWidth, alignment: .leading)
        .environment(\.colorScheme, .light)
        .background(Color.white)
    let renderer = ImageRenderer(content: document)
    renderer.scale = 1

    let pdfData = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

    renderer.render { contentSize, render in
        let pageCount = max(1, Int((contentSize.height / printableHeight).rounded(.up)))
        for pageIndex in 0 ..< pageCount {
            context.beginPDFPage(nil)
            context.saveGState()
            context.clip(to: CGRect(x: margins, y: margins + footerHeight,
                                    width: contentWidth, height: printableHeight))
            let yOffset = pageSize.height - margins - contentSize.height
                + CGFloat(pageIndex) * printableHeight
            context.translateBy(x: margins, y: yOffset)
            render(context)
            context.restoreGState()
            drawAttribution(sourceURL: sourceURL, page: pageIndex + 1, pageCount: pageCount,
                            context: context,
                            bounds: CGRect(x: margins, y: margins, width: contentWidth, height: 14))
            context.endPDFPage()
        }
    }
    context.closePDF()
    return pdfData as Data
}

private func drawAttribution(sourceURL: URL, page: Int, pageCount: Int,
                             context: CGContext, bounds: CGRect) {
    let source = String(sourceURL.absoluteString.prefix(180))
    let text = "\(source)  •  Page \(page) of \(pageCount)"
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 8, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.35, alpha: 1)
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.saveGState()
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: bounds.minX, y: bounds.minY + 3)
    context.clip(to: bounds)
    CTLineDraw(line, context)
    context.restoreGState()
}

@MainActor
private func attributedPrintPageSize() -> CGSize {
    #if os(macOS)
        let size = NSPrintInfo.shared.paperSize
        return size.width > 0 && size.height > 0 ? size : CGSize(width: 612, height: 792)
    #else
        return CGSize(width: 612, height: 792)
    #endif
}

@MainActor
private func presentAttributedPrintPanel(data: Data, pageSize: CGSize, jobTitle: String) {
    #if os(macOS)
        guard let document = PDFDocument(data: data) else { return }

        let info = NSPrintInfo()
        info.paperSize = pageSize
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleNone,
                                                      autoRotate: false) else { return }

        operation.jobTitle = jobTitle
        operation.run()
    #else
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = jobTitle
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
    #endif
}
