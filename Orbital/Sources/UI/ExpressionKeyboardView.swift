//
//  ExpressionKeyboardView.swift
//  Orbital
//
//  Custom keyboard layout for editing arithmetic expressions.
//

import SwiftUI

// MARK: - Keyboard Action

enum ExpressionKeyboardAction {
  case insert(String)
  case backspace
  case done
}

// MARK: - Top-Level Keyboard View

struct ExpressionKeyboardView: View {
  let emitterNames: [String]
  let onAction: (ExpressionKeyboardAction) -> Void

  var body: some View {
    VStack(spacing: 0) {
      EmitterNameRow(emitterNames: emitterNames, onAction: onAction)
      Divider()
      KeyGridView(onAction: onAction)
    }
    .frame(height: 260)
    .background(.regularMaterial)
  }
}

// MARK: - Emitter Name Row

private struct EmitterNameRow: View {
  let emitterNames: [String]
  let onAction: (ExpressionKeyboardAction) -> Void

  var body: some View {
    ScrollView(.horizontal) {
      HStack {
        ForEach(emitterNames, id: \.self) { name in
          Button(name) {
            onAction(.insert(name))
          }
          .buttonStyle(.bordered)
          .font(.system(.callout, design: .monospaced))
        }
        Button("eventNote") {
          onAction(.insert("eventNote"))
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .font(.system(.callout, design: .monospaced))
        Button("eventVelocity") {
          onAction(.insert("eventVelocity"))
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .font(.system(.callout, design: .monospaced))
      }
      .padding(.horizontal)
    }
    .scrollIndicators(.hidden)
    .frame(height: 44)
  }
}

// MARK: - Key Grid

private struct KeyGridView: View {
  let onAction: (ExpressionKeyboardAction) -> Void

  // Row 1:  7  8  9  /  (
  // Row 2:  4  5  6  *  )
  // Row 3:  1  2  3  -  ⌫
  // Row 4:  0  .  +  ␣  Done

  private let rows: [[KeyDef]] = [
    [.char("7"), .char("8"), .char("9"), .char("/"), .char("(")],
    [.char("4"), .char("5"), .char("6"), .char("*"), .char(")")],
    [.char("1"), .char("2"), .char("3"), .char("-"), .backspace],
    [.char("0"), .char("."), .char("+"), .space, .done],
  ]

  var body: some View {
    VStack(spacing: 8) {
      ForEach(rows.indices, id: \.self) { rowIndex in
        HStack(spacing: 6) {
          ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
            ExpressionKeyButton(
              key: rows[rowIndex][colIndex],
              onAction: onAction
            )
          }
        }
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 8)
  }
}

// MARK: - Key Definition

private enum KeyDef {
  case char(String)
  case backspace
  case done
  case space
}

// MARK: - Key Button

private struct ExpressionKeyButton: View {
  let key: KeyDef
  let onAction: (ExpressionKeyboardAction) -> Void

  var body: some View {
    Button {
      switch key {
      case .char(let ch):
        onAction(.insert(ch))
      case .backspace:
        onAction(.backspace)
      case .done:
        onAction(.done)
      case .space:
        onAction(.insert(" "))
      }
    } label: {
      ExpressionKeyLabel(key: key)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 6))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Key Label

private struct ExpressionKeyLabel: View {
  let key: KeyDef

  var body: some View {
    switch key {
    case .char(let ch):
      Text(ch)
        .font(.system(.title3, design: .monospaced))
    case .backspace:
      Image(systemName: "delete.backward")
        .font(.title3)
    case .done:
      Text("Done")
        .font(.callout)
        .bold()
        .foregroundStyle(.tint)
    case .space:
      Image(systemName: "space")
        .font(.title3)
    }
  }
}
