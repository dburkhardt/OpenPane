import PDFKit
import Testing
@testable import OpenPane

@Suite("PDF reader")
struct PDFReaderTests {
    @Test("Existing PDF annotations are made read-only in memory")
    func annotationsAreReadOnly() {
        let document = PDFDocument()
        let page = PDFPage()
        let annotation = PDFAnnotation(
            bounds: CGRect(x: 10, y: 10, width: 100, height: 24),
            forType: .widget,
            withProperties: nil
        )
        annotation.isReadOnly = false
        page.addAnnotation(annotation)
        document.insert(page, at: 0)

        PDFReadOnlyPolicy.apply(to: document)

        #expect(annotation.isReadOnly)
        #expect(page.annotations.count == 1)
    }
}
