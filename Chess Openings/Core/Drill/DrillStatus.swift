import Foundation
import ChessKit

enum DrillStatus: Equatable {
    case waitingForUser
    case evaluating
    case mistake(book: BookCandidate, played: Move)
    case lineComplete
}
