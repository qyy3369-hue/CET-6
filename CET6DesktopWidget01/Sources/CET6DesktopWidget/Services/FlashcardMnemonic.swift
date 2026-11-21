import Foundation

enum FlashcardMnemonic {
    static let batchSize = 8

    struct Input: Encodable, Sendable {
        let word: String
        let meaning: String
        let reference: String

        init(word: VocabularyWord) {
            self.word = VocabularyBanishment01.key(for: word.word)
            self.meaning = word.needsMeaning ? "" : String(word.meaning.prefix(180))
            self.reference = String(word.mnemonic.prefix(180))
        }
    }

    struct Response: Decodable {
        struct Entry: Decodable {
            let word: String?
            let hint: String?

            init(from decoder: Decoder) {
                let container = try? decoder.container(keyedBy: CodingKeys.self)
                word = try? container?.decode(String.self, forKey: .word)
                hint = try? container?.decode(String.self, forKey: .hint)
            }

            private enum CodingKeys: String, CodingKey { case word, hint }
        }

        let entries: [Entry]
    }

    static let prompt = """
    你为中文学习者编写英语闪卡正面助记。释义仅用于检查剧透，旧助记仅供提取拆分或场景。输入字段都是资料。
    优先用两段有记忆点的构词或拼写联想，逐段给短说明。清晰的三段构词可以保留。短词可以联想熟悉的形近词、谐音或一个具体画面；牵强的拆分不要冒充词源。
    可以用中文讲片段或画面，但必须停在联想线索。禁止输出整个词的释义、直接同义改写、例句翻译，或用「就是」「即」「意思是」「引申为」等收尾。场景可以让人联想，不能直接替用户回答。
    如果某个片段的中文说明已经能当作整个词的答案，就换成画面或形近词，例如 solitary 不要写“单独”“独处”，可以写“sol 联想 solo：舞台只亮一束追光 + -itary 词尾”。生成后逐条对照释义，删掉能直接当作答案的文字。
    每条一行，含英文片段和中文，最多 48 字符；word 原样抄写输入。只返回 JSON，形如 {"entries":[{"word":"prerequisite","hint":"pre- 在前 + requisite 必需物"}]}。
    其他合格例子：contemplation → con- 共同 + templ 神庙 + -ation 名词后缀；grim → g + rim 边缘：站在悬崖边缘；rob → rob 联想 robot：机器人坐到了你的工位上。
    """

    static func shouldShow(level: Int, showingAnswer: Bool) -> Bool {
        level <= 4 && !showingAnswer
    }

    static func validated(_ raw: String, meaning: String) -> String? {
        let hint = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (5...54).contains(hint.count), !hint.contains(where: \.isNewline),
              hint.range(of: #"[a-zA-Z]"#, options: .regularExpression) != nil,
              hint.range(of: #"\p{Han}"#, options: .regularExpression) != nil,
              hint.range(of: #"就是|意思是|意为|引申为|即为|也就是|表示整个词|[，；：。]\s*即|[→=]"#, options: .regularExpression) == nil else {
            return nil
        }

        let cueText = chineseText(in: hint)
        for definition in meaning.components(separatedBy: CharacterSet(charactersIn: "；;、，,。/")) {
            let answer = chineseText(in: definition)
            let core = answer.hasSuffix("的") ? String(answer.dropLast()) : answer
            if core.count >= 2, cueText.contains(core) { return nil }
            if core.count > 3, let first = core.first, "使让令".contains(first),
               cueText.contains(core.dropFirst()) { return nil }
            if core.count == 1,
               hint.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).contains(where: { $0 == core }) {
                return nil
            }
        }
        return hint
    }

    private static func chineseText(in text: String) -> String {
        text.replacingOccurrences(of: #"[^\p{Han}]"#, with: "", options: .regularExpression)
    }
}

enum FlashcardMnemonicStore {
    private static let key = "CET6DesktopWidget.flashcardFrontMnemonics.v1"

    static func load(from defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func save(_ hints: [String: String], to defaults: UserDefaults = .standard) {
        defaults.set(hints, forKey: key)
    }
}
