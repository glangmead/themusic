//
//  ExpressionTextField.swift
//  Orbital
//
//  UIViewRepresentable wrapping UITextField with a custom expression keyboard
//  as its inputView.
//

import SwiftUI
import UIKit

struct ExpressionTextField: UIViewRepresentable {
  @Binding var text: String
  let placeholder: String
  let emitterNames: [String]

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeUIView(context: Context) -> UITextField {
    let textField = UITextField()
    textField.placeholder = placeholder
    textField.font = UIFont.monospacedSystemFont(
      ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
      weight: .regular
    )
    textField.autocorrectionType = .no
    textField.autocapitalizationType = .none
    textField.spellCheckingType = .no
    textField.borderStyle = .none
    textField.delegate = context.coordinator

    // Build the custom keyboard and set it as the inputView.
    let hostingController = makeKeyboardHostingController(
      textField: textField,
      emitterNames: emitterNames
    )
    textField.inputView = hostingController.view
    context.coordinator.keyboardHostingController = hostingController

    return textField
  }

  func updateUIView(_ textField: UITextField, context: Context) {
    if textField.text != text {
      textField.text = text
    }
    // Rebuild the keyboard when emitter names change.
    if let hostingController = context.coordinator.keyboardHostingController {
      hostingController.rootView = ExpressionKeyboardView(
        emitterNames: emitterNames,
        onAction: { [weak textField] action in
          guard let textField else { return }
          Self.handleAction(action, textField: textField)
        }
      )
    }
  }

  // MARK: - Keyboard Construction

  private func makeKeyboardHostingController(
    textField: UITextField,
    emitterNames: [String]
  ) -> UIHostingController<ExpressionKeyboardView> {
    let keyboardView = ExpressionKeyboardView(
      emitterNames: emitterNames,
      onAction: { [weak textField] action in
        guard let textField else { return }
        Self.handleAction(action, textField: textField)
      }
    )

    let hostingController = UIHostingController(rootView: keyboardView)
    hostingController.view.autoresizingMask = UIView.AutoresizingMask.flexibleWidth

    // Size to fit the keyboard's intrinsic height.
    let fittingSize = hostingController.sizeThatFits(in: CGSize(
      width: textField.bounds.width > 0 ? textField.bounds.width : 400,
      height: .infinity
    ))
    hostingController.view.frame = CGRect(
      origin: .zero,
      size: CGSize(width: fittingSize.width, height: fittingSize.height)
    )

    return hostingController
  }

  private static func handleAction(
    _ action: ExpressionKeyboardAction,
    textField: UITextField
  ) {
    switch action {
    case .insert(let string):
      textField.insertText(string)
    case .backspace:
      textField.deleteBackward()
    case .done:
      let expression = textField.text ?? ""
      // Empty is fine — it clears the expression.
      guard !expression.isEmpty else {
        textField.resignFirstResponder()
        return
      }
      do {
        _ = try QuickParser.parse(expression)
        textField.resignFirstResponder()
      } catch {
        let alert = UIAlertController(
          title: "Invalid Expression",
          message: "\(error)",
          preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        // Present on the topmost view controller so the alert appears above sheets.
        if let presenter = textField.window?.rootViewController {
          var top = presenter
          while let presented = top.presentedViewController {
            top = presented
          }
          top.present(alert, animated: true)
        }
      }
    }
  }

  // MARK: - Coordinator

  @MainActor
  final class Coordinator: NSObject, UITextFieldDelegate {
    var text: Binding<String>
    var keyboardHostingController: UIHostingController<ExpressionKeyboardView>?

    init(text: Binding<String>) {
      self.text = text
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
      let newText = textField.text ?? ""
      if text.wrappedValue != newText {
        text.wrappedValue = newText
      }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      ExpressionTextField.handleAction(.done, textField: textField)
      return false
    }
  }
}
