//
//  PresetCell.swift
//  Orbital
//

import SwiftUI

struct PresetCell: View {
  let name: String
  let onSettings: () -> Void

  var body: some View {
    HStack {
      Text(name)
      Spacer()
      Button(action: onSettings) {
        Image(systemName: "slider.horizontal.3")
      }
      .buttonStyle(.borderless)
    }
  }
}
