import AppKit
import QuickLookUI
import SwiftUI

/// Read-only system preview for images, media, Office documents, and archives.
/// OpenPane does not provide editing controls or execute embedded document code.
struct SystemPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)
        preview?.autostarts = false
        preview?.shouldCloseWithWindow = false
        preview?.previewItem = url as NSURL
        return preview ?? QLPreviewView(frame: .zero, style: .compact)!
    }

    func updateNSView(_ preview: QLPreviewView, context: Context) {
        let currentURL = (preview.previewItem as? NSURL) as URL?
        if currentURL?.standardizedFileURL != url.standardizedFileURL {
            preview.previewItem = url as NSURL
            preview.refreshPreviewItem()
        }
    }

    static func dismantleNSView(_ preview: QLPreviewView, coordinator: ()) {
        preview.close()
    }
}
