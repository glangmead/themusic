//
//  Theme.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/21/25.
//


import Foundation
import SwiftUI

struct Theme {

    /// Theme color for sound waves, lights.
    static let colorHighlight = Color(hex: 0x4fbcd4)

    /// 0x222222
    static let colorGray1 = Color(hex: 0x222222)
    /// 0x333333
    static let colorGray2 = Color(hex: 0x333333)
    /// 0x4a4a4a
    static let colorGray3 = Color(hex: 0x4a4a4a)
    /// 0x666666
    static let colorGray4 = Color(hex: 0x666666)

    /// Main texts.
    static let colorBodyText = Color(hex: 0xcccccc)

    static let colorTitleText = Color.white

    static let gradientKnob = LinearGradient(gradient: Gradient(
        colors: [Color(hex: 0x151515), Color(hex: 0x131313)]), startPoint: .top, endPoint: .bottom)

    static let fontBody = Font.system(size: 13.0)

    /// Main gradient used in the app home background.
    static func gradientMain() -> LinearGradient {
        return LinearGradient(colors: [Color(hex: 0x4a4a4a), Color(hex: 0x000000)], startPoint: .top, endPoint: .bottom)
    }

    /// Radial gradient for a light screen, used in selected waveforms.
    static func gradientLightScreen(_ radius: CGFloat = 200.0) -> RadialGradient {
        return RadialGradient(colors: [Color(hex: 0x003849), Color(hex: 0x000000)], center: .top, startRadius: 0, endRadius: radius)
    }

    /// Radial gradient for a darkened screen, used as screen backgrounds.
    static func gradientDarkScreen(_ radius: CGFloat = 200.0) -> RadialGradient {
        return RadialGradient(colors: [Color(hex: 0x333333), Color(hex: 0x000000)], center: .top, startRadius: 0, endRadius: radius)
    }

    static func gradientBlankScreen() -> RadialGradient {
        return RadialGradient(colors: [Theme.colorGray2], center: .top, startRadius: 0, endRadius: 1)
    }

    /// Linear gradient used for art titles.
    static func gradientArtTitle() -> LinearGradient {
        return LinearGradient(colors: [Color(hex: 0xffffff), Color(hex: 0xffffff, alpha: 0.5)], startPoint: .top, endPoint: .bottom)
    }

}

extension Color {
  
  /// Initiate SwiftUI colors with hex code.
  init(hex: UInt, alpha: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xff) / 255,
      green: Double((hex >> 08) & 0xff) / 255,
      blue: Double((hex >> 00) & 0xff) / 255,
      opacity: alpha
    )
  }
  
  var uiColor: UIColor {
    return UIColor(self)
  }
}

