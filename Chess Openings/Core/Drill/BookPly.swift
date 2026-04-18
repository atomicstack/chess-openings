import Foundation

struct BookPly: Codable, Hashable, Sendable {
    var san: String
    var uci: String
    var annotation: String?
    var alternativeSans: [String]

    init(san: String, uci: String, annotation: String? = nil, alternativeSans: [String] = []) {
        self.san = san
        self.uci = uci
        self.annotation = annotation
        self.alternativeSans = alternativeSans
    }
}
