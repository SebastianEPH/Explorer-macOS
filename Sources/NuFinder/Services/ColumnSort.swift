import Foundation
import SwiftUI

/// Fork: clic en el título de una columna de la vista de lista (Nombre, Tipo, Tamaño, Fecha)
/// para ordenar por ella; otro clic invierte el orden. El orden real lo sigue haciendo
/// BrowserModel con `sortCriteria`, esto solo traduce entre la tabla y esos criterios.
struct ColumnSortComparator: SortComparator, Hashable {
    var field: SortField
    var order: SortOrder = .forward

    func compare(_ lhs: FileItem, _ rhs: FileItem) -> ComparisonResult {
        let result: ComparisonResult
        switch field {
        case .name, .created: result = lhs.name.localizedStandardCompare(rhs.name)
        case .kind: result = lhs.kind.localizedStandardCompare(rhs.kind)
        case .size: result = lhs.size == rhs.size ? .orderedSame : (lhs.size < rhs.size ? .orderedAscending : .orderedDescending)
        case .modified:
            let l = lhs.modified ?? .distantPast, r = rhs.modified ?? .distantPast
            result = l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
        }
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}

extension BrowserModel {
    /// La columna por la que se ordena (la primera de `sortCriteria`) para la tabla.
    var columnSortOrder: Binding<[ColumnSortComparator]> {
        Binding(
            get: {
                self.sortCriteria.map { ColumnSortComparator(field: $0.field, order: $0.ascending ? .forward : .reverse) }
            },
            set: { newValue in
                guard let first = newValue.first else { return }
                self.sortCriteria = [SortCriterion(field: first.field, ascending: first.order == .forward)]
            }
        )
    }
}
