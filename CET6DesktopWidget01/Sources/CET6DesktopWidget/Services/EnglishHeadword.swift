import Foundation
import NaturalLanguage

enum EnglishHeadword {
    static func baseForm(_ token: String) -> String {
        let word = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard word.range(of: #"^[a-z]+$"#, options: .regularExpression) != nil else { return word }

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        let lemma = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0?.rawValue.lowercased()
        guard let lemma, lemma.range(of: #"^[a-z]+$"#, options: .regularExpression) != nil else { return word }
        return lemma
    }
}
