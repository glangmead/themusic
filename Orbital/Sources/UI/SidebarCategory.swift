//
//  SidebarCategory.swift
//  Orbital
//

import Foundation

enum SidebarCategory: String, CaseIterable, Identifiable {
  case nowPlaying = "Now Playing"
  case songs = "Library"
  case classics = "Classics"
  case create = "Procedures"
  case soundDesign = "Sounds"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .nowPlaying: "play.circle.fill"
    case .songs: "music.note.list"
    case .classics: "building.columns"
    case .create: "list.bullet.indent"
    case .soundDesign: "horn"
    }
  }
}
