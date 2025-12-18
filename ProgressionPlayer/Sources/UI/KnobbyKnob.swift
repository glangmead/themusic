//
//  KnobbyKnob.swift
//  ProgressionPlayer
//
//  Created by Greg Langmead on 11/21/25.
//


import Foundation
import SwiftUI

struct KnobbyKnob<T: BinaryFloatingPoint>: View {
  @Binding var value: T
  @State private var isDragging = false
  @State private var oldValue: T = 0
  
  static func isInt(_ val: T) -> Bool {
    val - floor(val) < 0.001
  }
  
  var label: String = ""
  
  var range: ClosedRange<T> = 0...1
  var size: CGFloat = 80.0
  
  /// Set how many steps should the knob have.
  var stepSize: T = 0.01
  
  /// Set if when value = 0, the signal light will be turned gray.
  var allowPoweroff = false
  
  /// If show value on the know
  var ifShowValue = true
  
  /// Set the sensitivity of the dragging gesture.
  var sensitivity: T = 0.3
  
  var valueFormatter: ((T) -> String) = { isInt($0) ? String(format: "%.0f", $0 as! CVarArg) : String(format: "%.2f", $0 as! CVarArg) }
  
  var onChanged: ((T) -> Void)?
  
  let startingAngle: Angle = .radians(.pi / 6)
  
  var normalizedValue: T {
    T((value - range.lowerBound) / (range.upperBound - range.lowerBound))
  }
  
  var body: some View {
    VStack {
      ZStack {
        Circle()
          .shadow(color: Color(hex: 0x000000, alpha: 0.6), radius: 8.0, x: 0, y: 6.0)
          .foregroundStyle(Theme.gradientKnob)
          .frame(width: size, height: size)
          .overlay {
            Circle()
              .stroke(.white, lineWidth: 3.0)
              .blur(radius: 2.0)
              .offset(x: 0.0, y: 2.0)
              .opacity(0.25)
              .frame(width: size + 2.0, height: size + 2.0)
              .mask(Circle().frame(width: size, height: size))
          }
        
        if ifShowValue {
          KnobbyBox(isOn: false, blankStyle: false, width: size*0.9, height: 16) {
            Text(valueFormatter(value)).foregroundColor(Theme.colorBodyText)
          }
        }
        if allowPoweroff && normalizedValue == 0.0 {
          Circle()
            .fill(Theme.colorGray4)
            .frame(width: size / 12, height: size / 12.0)
            .offset(y: size / 2.0 * 0.7)
            .rotationEffect(startingAngle)
            .rotationEffect((.radians(2 * .pi) - startingAngle * 2) * Double(normalizedValue))
        } else {
          Circle()
            .fill(Theme.colorHighlight)
            .shadow(color: Theme.colorHighlight, radius: 5.0)
            .shadow(color: Theme.colorHighlight, radius: 10.0)
            .frame(width: size / 12, height: size / 12.0)
            .offset(y: size / 2.0 * 0.7)
            .rotationEffect(startingAngle)
            .rotationEffect((.radians(2 * .pi) - startingAngle * 2) * Double(normalizedValue))
        }
      }.gesture(DragGesture(minimumDistance: 0)
        .onChanged { value in
          updateValue(from: value)
        }
        .onEnded { _ in
          isDragging = false
        }
      )
      
      Text(label)
    }
  }
  
  private func updateValue(from value: DragGesture.Value) {
    if !isDragging {
      oldValue = self.value
      isDragging = true
    }
    let x = value.translation.width
    let y = -value.translation.height
    var offset: T = 0.0
    offset += T(x / size) * (range.upperBound - range.lowerBound) * sensitivity
    offset += T(y / size) * (range.upperBound - range.lowerBound) * sensitivity
    let clippedValue = max(range.lowerBound, min(range.upperBound, self.oldValue + offset))
    let steppedValue = (clippedValue / stepSize).rounded() * stepSize
    self.value = steppedValue
    if oldValue != steppedValue {
      self.onChanged?(steppedValue)
    }
  }
}


struct KnobbyKnob_Container<T: BinaryFloatingPoint>: View {
  @State var value: T = 0.5
  var body: some View {
    KnobbyKnob<T>(value: $value, label: "Testy")
  }
}

struct KnobbyKnob_Previews<T: BinaryFloatingPoint>: PreviewProvider {
  static var previews: some View {
    KnobbyKnob_Container<T>()
  }
}

#Preview {
  KnobbyKnob_Container<Float>()
}
