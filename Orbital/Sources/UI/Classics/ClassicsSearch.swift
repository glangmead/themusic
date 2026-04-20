//
//  ClassicsSearch.swift
//  Orbital
//
//  Token-based search over the Classics catalog at the works level.
//  The query is split on whitespace; a work matches when every token is
//  found (via `localizedStandardContains`) inside the haystack formed by
//  composer name, work title, catalog label, and key.
//

import Foundation

enum ClassicsSearch {
  static func tokens(for query: String) -> [String] {
    query.split(whereSeparator: \.isWhitespace).map(String.init)
  }

  static func matches(composer: CatalogComposer, work: CatalogWork, tokens: [String]) -> Bool {
    guard !tokens.isEmpty else { return true }
    let haystack = [
      composer.name,
      work.title,
      work.catalogLabel ?? "",
      work.key ?? ""
    ].joined(separator: " ")
    return tokens.allSatisfy { haystack.localizedStandardContains($0) }
  }
}

/// Composer + work pair returned by a global Classics search. Identified
/// by composer slug plus work id because `CatalogWork.id` falls back to
/// title and can collide across composers.
struct ClassicsSearchItem: Identifiable, Hashable {
  let composer: CatalogComposer
  let work: CatalogWork
  var id: String { "\(composer.slug):\(work.id)" }

  static func == (lhs: ClassicsSearchItem, rhs: ClassicsSearchItem) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}
