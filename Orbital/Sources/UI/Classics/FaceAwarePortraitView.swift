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

struct FaceAwarePortraitView: View {
  let url: URL
  var frameHeight: CGFloat = 250

  @State private var uiImage: UIImage?
  /// Face center Y normalized to image height (0 = top, 1 = bottom). Nil until detection completes.
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
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .task(id: url) {
      await loadAndDetect()
    }
  }

  // MARK: - Offset computation

  private func computeOffset(displayHeight: CGFloat) -> CGFloat {
    // Place the face center at 40% down the frame. Falls back to the upper quarter of the image.
    let facePx = (faceFractionY ?? 0.25) * displayHeight
    let targetY = frameHeight * 0.4
    let raw = targetY - facePx
    // Clamp: image top can't go below frame top (offset ≤ 0);
    //        image bottom can't go above frame bottom (offset ≥ frameHeight - displayHeight).
    return min(0, max(frameHeight - displayHeight, raw))
  }

  // MARK: - Loading & detection

  private func loadAndDetect() async {
    guard let (data, _) = try? await URLSession.shared.data(from: url),
          let image = UIImage(data: data)
    else { return }

    uiImage = image
    faceFractionY = await detectFaceCenterY(in: image)
  }

  private func detectFaceCenterY(in image: UIImage) async -> CGFloat? {
    guard let cgImage = image.cgImage else { return nil }
    return await Task.detached(priority: .userInitiated) {
      let request = VNDetectFaceRectanglesRequest()
      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      try? handler.perform([request])
      guard let face = request.results?.first else { return nil }
      // VNFaceObservation.boundingBox uses bottom-left origin (Vision flips Y vs UIKit).
      // Convert face center midY to UIKit coords where 0 = top of image.
      return CGFloat(1.0 - face.boundingBox.midY)
    }.value
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
