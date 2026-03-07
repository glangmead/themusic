//
//  FaceAwarePortraitView.swift
//  Orbital
//
//  Loads a portrait image from a URL, detects the face using Vision,
//  then crops the display frame so the face is centered at ~40% of the
//  frame height rather than letting the clipping cut it off.
//

import SwiftUI
import Vision

// MARK: - Shared portrait cache

/// Caches downloaded images and their face-center Y fraction so each URL
/// is only fetched and analysed once across the lifetime of the app.
private final class PortraitImageCache: Sendable {
  static let shared = PortraitImageCache()

  struct Entry: Sendable {
    let image: UIImage
    let faceFractionY: CGFloat?
  }

  private let cache = NSCache<NSURL, Box>()

  // NSCache requires class values
  private final class Box: Sendable {
    let entry: Entry
    init(_ entry: Entry) { self.entry = entry }
  }

  func get(_ url: URL) -> Entry? {
    cache.object(forKey: url as NSURL)?.entry
  }

  func set(_ entry: Entry, for url: URL) {
    cache.setObject(Box(entry), forKey: url as NSURL)
  }
}

struct FaceAwarePortraitView: View {
  let url: URL
  var frameHeight: CGFloat = 250

  @State private var uiImage: UIImage?
  @State private var faceFractionY: CGFloat?

  var body: some View {
    GeometryReader { geo in
      Color.secondary.opacity(0.2)
        .frame(width: geo.size.width, height: frameHeight)
        .overlay(alignment: .top) {
          if let image = uiImage {
            let scale = geo.size.width / image.size.width
            let displayHeight = image.size.height * scale
            let offset = computeOffset(displayHeight: displayHeight)
            Image(uiImage: image)
              .resizable()
              .frame(width: geo.size.width, height: displayHeight)
              .offset(y: offset)
          }
        }
        .clipped()
    }
    .frame(height: frameHeight)
    .clipShape(.rect(cornerRadius: 12))
    .task(id: url) {
      await loadAndDetect()
    }
  }

  // MARK: - Offset computation

  private func computeOffset(displayHeight: CGFloat) -> CGFloat {
    let facePx = (faceFractionY ?? 0.25) * displayHeight
    let targetY = frameHeight * 0.4
    let raw = targetY - facePx
    return min(0, max(frameHeight - displayHeight, raw))
  }

  // MARK: - Loading & detection

  private func loadAndDetect() async {
    // Check cache first
    if let cached = PortraitImageCache.shared.get(url) {
      uiImage = cached.image
      faceFractionY = cached.faceFractionY
      return
    }

    // Detach the download so SwiftUI task cancellation doesn't abort it
    guard let entry = await Task.detached(priority: .userInitiated) { [url] () -> PortraitImageCache.Entry? in
      let data: Data
      do {
        let (d, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
          print("[Portrait] HTTP \(http.statusCode) for \(url.absoluteString)")
          return nil
        }
        data = d
      } catch {
        print("[Portrait] Network error for \(url.absoluteString): \(error.localizedDescription)")
        return nil
      }
      guard let image = UIImage(data: data) else {
        print("[Portrait] Could not decode image (\(data.count) bytes) from \(url.absoluteString)")
        return nil
      }
      let faceY = Self.detectFaceCenterYSync(in: image)
      let entry = PortraitImageCache.Entry(image: image, faceFractionY: faceY)
      PortraitImageCache.shared.set(entry, for: url)
      return entry
    }.value else { return }

    uiImage = entry.image
    faceFractionY = entry.faceFractionY
  }

  private static func detectFaceCenterYSync(in image: UIImage) -> CGFloat? {
    guard let cgImage = image.cgImage else { return nil }
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([request])
    guard let face = request.results?.first else { return nil }
    return CGFloat(1.0 - face.boundingBox.midY)
  }


}

#Preview {
  FaceAwarePortraitView(
    url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/4/4f/DufayBinchois.jpg")!,
    frameHeight: 250
  )
  .frame(maxWidth: .infinity)
  .padding()
}
