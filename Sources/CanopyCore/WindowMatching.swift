import Foundation

public struct WindowFingerprint: Sendable {
    public var bundle: String
    public var title: String
    public var ordinal: Int
    public var identifier: String?
    public var document: String?
    public var frame: LayoutRect
    public init(bundle: String,title: String,ordinal: Int,identifier: String? = nil,document: String? = nil,frame: LayoutRect) {
        self.bundle = bundle; self.title = title; self.ordinal = ordinal; self.identifier = identifier
        self.document = document; self.frame = frame
    }
}

public enum WindowMatcher {
    /// Ambiguous candidates deliberately stay unmatched instead of stealing another window's place.
    public static func match(_ incoming: WindowFingerprint, candidates: [(id: String, fingerprint: WindowFingerprint)]) -> String? {
        var ranked: [(String,Double)] = []
        for candidate in candidates where candidate.fingerprint.bundle == incoming.bundle {
            let f = candidate.fingerprint
            var score = 0.0
            if let identifier = incoming.identifier, !identifier.isEmpty, identifier == f.identifier { score += 150 }
            if let document = incoming.document, !document.isEmpty, document == f.document { score += 100 }
            if !incoming.title.isEmpty, incoming.title == f.title { score += 70 }
            let distance = abs(incoming.frame.width-f.frame.width)+abs(incoming.frame.height-f.frame.height)
            if distance < 8 { score += 22 }
            if abs(incoming.frame.x-f.frame.x)+abs(incoming.frame.y-f.frame.y) < 12 { score += 12 }
            if incoming.ordinal == f.ordinal { score += 8 }
            ranked.append((candidate.id,score))
        }
        ranked.sort { a,b in a.1 == b.1 ? a.0 < b.0 : a.1 > b.1 }
        guard let best = ranked.first, best.1 >= 40 else { return nil }
        if ranked.count > 1, best.1-ranked[1].1 < 5 { return nil }
        return best.0
    }
}
