import Foundation
import AVFoundation

struct CaptionLine: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var languageCode: String // e.g., "en", "fr"
    var start: CMTime
    var end: CMTime
    var text: String
}

extension Array where Element == CaptionLine {
    func activeCaption(at time: CMTime, languageCode: String?) -> CaptionLine? {
        let lang = languageCode
        return first(where: { (lang == nil || $0.languageCode == lang) && CMTimeCompare(time, $0.start) >= 0 && CMTimeCompare(time, $0.end) < 0 })
    }
    var languages: [String] {
        let codes = self.map { $0.languageCode }
        let unique = Set<String>(codes)
        return [String](unique).sorted()
    }
}


