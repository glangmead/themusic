//
//  MIDIWebView.swift
//  Orbital
//
//  A WKWebView wrapper that opens a URL (typically kunstderfuge.com) and
//  intercepts MIDI file downloads, saving them to the app's midi_downloads
//  directory and recording them in the ledger.
//

import SwiftUI
import WebKit
import OSLog

private let logger = Logger(subsystem: "com.langmead.Orbital", category: "MIDIWebView")

struct MIDIWebView: UIViewRepresentable {
  let url: URL
  let composerSlug: String
  let ledger: MIDIDownloadLedger
  let onDownloadComplete: (String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(composerSlug: composerSlug, ledger: ledger, sourceUrlString: url.absoluteString,
                onDownloadComplete: onDownloadComplete)
  }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = context.coordinator
    #if DEBUG
    webView.isInspectable = true
    #endif
    webView.load(URLRequest(url: url))
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}

  // MARK: - Coordinator

  final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    let composerSlug: String
    let ledger: MIDIDownloadLedger
    let sourceUrlString: String
    let onDownloadComplete: (String) -> Void

    private var pendingSourceUrl: String?
    private var pendingDestURL: URL?

    init(composerSlug: String, ledger: MIDIDownloadLedger, sourceUrlString: String,
         onDownloadComplete: @escaping (String) -> Void) {
      self.composerSlug = composerSlug
      self.ledger = ledger
      self.sourceUrlString = sourceUrlString
      self.onDownloadComplete = onDownloadComplete
    }

    // MARK: WKNavigationDelegate

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
      let mimeType = navigationResponse.response.mimeType ?? ""
      let url = navigationResponse.response.url?.absoluteString ?? ""

      // MIDI content type
      if mimeType.contains("midi") {
        return .download
      }

      // Binary response with .mid in URL (path or query parameter)
      if mimeType == "application/octet-stream" && url.contains(".mid") {
        return .download
      }

      // kdf midi.asp endpoint — always serves MIDI data regardless of reported MIME type
      if url.contains("midi.asp") {
        return .download
      }

      // URL path ends in .mid
      if let responseURL = navigationResponse.response.url,
         responseURL.pathExtension.lowercased() == "mid" {
        return .download
      }

      // Content-Disposition: attachment header
      if let httpResponse = navigationResponse.response as? HTTPURLResponse,
         let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
         disposition.contains("attachment") {
        return .download
      }

      // Non-HTML content that WebView can't display (binary data)
      if !navigationResponse.canShowMIMEType {
        return .download
      }

      return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
      pendingSourceUrl = navigationAction.request.url?.absoluteString ?? sourceUrlString
      download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
      pendingSourceUrl = navigationResponse.response.url?.absoluteString ?? sourceUrlString
      download.delegate = self
    }

    // MARK: WKDownloadDelegate

    func download(
      _ download: WKDownload,
      decideDestinationUsing response: URLResponse,
      suggestedFilename: String
    ) async -> URL? {
      let composerDir = ledger.baseDirectory.appending(path: composerSlug)
      try? FileManager.default.createDirectory(at: composerDir, withIntermediateDirectories: true)

      let filename: String
      if suggestedFilename.hasSuffix(".mid") {
        filename = MIDIDownloadManager.localFilename(
          from: suggestedFilename, existingIn: composerDir
        )
      } else {
        let sourceUrl = pendingSourceUrl ?? sourceUrlString
        filename = MIDIDownloadManager.localFilename(from: sourceUrl, existingIn: composerDir)
      }

      let destURL = composerDir.appending(path: filename)
      pendingDestURL = destURL
      return destURL
    }

    func downloadDidFinish(_ download: WKDownload) {
      guard let destURL = pendingDestURL ?? findDownloadedFile() else {
        logger.warning("Download finished but no destination URL available")
        return
      }

      let filename = destURL.lastPathComponent
      let relativePath = "\(composerSlug)/\(filename)"
      let sourceUrl = pendingSourceUrl ?? sourceUrlString

      Task { @MainActor in
        ledger.record(sourceUrl: sourceUrl, composerSlug: composerSlug, localPath: relativePath)
        logger.info("WebView download complete: \(relativePath)")
        onDownloadComplete(sourceUrl)
      }
    }

    func download(_ download: WKDownload, didFailWithError error: Error,
                  resumeData: Data?) {
      logger.error("WebView download failed: \(error.localizedDescription)")
    }

    private func findDownloadedFile() -> URL? {
      // Fallback: check the composer directory for most recently modified .mid file
      let composerDir = ledger.baseDirectory.appending(path: composerSlug)
      guard let contents = try? FileManager.default.contentsOfDirectory(
        at: composerDir, includingPropertiesForKeys: [.contentModificationDateKey]
      ) else { return nil }

      return contents
        .filter { $0.pathExtension == "mid" }
        .sorted {
          let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
          let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
          return d1 > d2
        }
        .first
    }
  }
}
