//
//  SidebarCategory.swift
//  Orbital
//

import Foundation

enum SidebarCategory: String, CaseIterable, Identifiable {
  case songs = "Songs"
  case classics = "Classics"
  case create = "Create"
  case soundLibrary = "Sound Library"
  case soundDesign = "Sound Design"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .songs: "music.note.list"
    case .classics: "building.columns"
    case .create: "wand.and.stars"
    case .soundLibrary: "pianokeys"
    case .soundDesign: "slider.horizontal.3"
    }
  }
}
