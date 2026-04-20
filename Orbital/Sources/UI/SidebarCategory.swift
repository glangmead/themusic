//
//  SidebarCategory.swift
//  Orbital
//

import Foundation

enum SidebarCategory: String, CaseIterable, Identifiable {
  case songs = "Library"
  case classics = "Classics"
  case create = "Procedures"
  case soundDesign = "Sounds"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .songs: "music.note.list"
    case .classics: "building.columns"
    case .create: "list.bullet.indent"
    case .soundDesign: "slider.horizontal.3"
    }
  }
}
