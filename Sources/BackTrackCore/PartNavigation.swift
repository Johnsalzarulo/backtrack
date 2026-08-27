import Foundation

package enum PartNavigation {
    package static func wrappedIndex(current: Int, direction: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((current + direction) % count + count) % count
    }
}
