import Foundation
@_exported import ChessKit

typealias Position = ChessKit.Position
typealias Move = ChessKit.Move
typealias Square = ChessKit.Square
typealias Board = ChessKit.Board

extension Side {
    /// The chesskit-native colour corresponding to this side.
    var ckColor: Piece.Color {
        switch self {
        case .white: return .white
        case .black: return .black
        }
    }
}

extension Piece.Color {
    /// The `Side` value corresponding to this chesskit colour.
    var side: Side {
        switch self {
        case .white: return .white
        case .black: return .black
        }
    }
}
