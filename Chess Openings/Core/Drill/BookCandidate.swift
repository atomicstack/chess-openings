import Foundation
import ChessKit

struct BookCandidate: Hashable {
    let move: Move
    let san: String
    let annotation: String?
}
