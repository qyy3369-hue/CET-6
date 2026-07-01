import Foundation

struct DeepSeekPlanService {
    enum ServiceError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "没有在 .env 或环境变量里找到 DEEPSEEK_API_KEY。"
            case .invalidResponse:
                return "DeepSeek 返回内容无法解析为日程。"
            case .requestFailed(let message):
                return message
            }
        }
    }

    private let apiKey: String
    private let model: String
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private let decoder = JSONDecoder()

    init(env: [String: String] = EnvLoader.load()) throws {
        guard let apiKey = env["DEEPSEEK_API_KEY"], !apiKey.isEmpty else {
            throw ServiceError.missingAPIKey
        }

        self.apiKey = apiKey
        self.model = env["DEEPSEEK_MODEL"].flatMap { $0.isEmpty ? nil : $0 } ?? "deepseek-v4-flash"
    }

    func generateSchedule(from planText: String) async throws -> [ScheduleBlock] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let today = DateKey.today()
        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是 CET-6 学习计划助理。请把用户的计划书拆成清晰日程。
                    当前年份是 \(currentYear)，今天是 \(today)。
                    用户写“5月24日”时，dateKeys 必须输出 "\(currentYear)-05-24" 这样的 yyyy-MM-dd。
                    用户写“5月23 24”“5月23日、24日”“5月23和24日”这类同一任务跨多个日期时，dateKeys 必须包含每一个日期，同一个任务会由客户端展开到多天日程。
                    只输出 JSON，不要 Markdown，不要解释。
                    JSON 格式必须是：
                    {"schedule":[{"dateKeys":["\(currentYear)-05-24"],"timeLabel":"全天","title":"高频词 60 个","note":"重点看同义替换","category":"词汇"}]}
                    category 只能从 词汇、听力、阅读、输出、复习 中选择。
                    """
                ),
                ChatMessage(role: "user", content: planText)
            ],
            temperature: 0.2,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 1200,
            responseFormat: ResponseFormat(type: "json_object")
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(DeepSeekErrorResponse.self, from: data)
            throw ServiceError.requestFailed(apiError?.error.message ?? "DeepSeek 请求失败：HTTP \(httpResponse.statusCode)")
        }

        let completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content,
              let contentData = Self.cleanedJSONContent(content).data(using: .utf8) else {
            throw ServiceError.invalidResponse
        }

        let decoded: GeneratedSchedule
        do {
            decoded = try decoder.decode(GeneratedSchedule.self, from: contentData)
        } catch {
            throw ServiceError.requestFailed("DeepSeek 返回 JSON 格式不符合日程结构：\(error.localizedDescription)")
        }
        let schedule = decoded.schedule
            .flatMap { item in
                item.normalizedDateKeys().map { dateKey in
                    ScheduleBlock(
                        dateKey: dateKey,
                        timeLabel: item.timeLabel?.isEmpty == false ? item.timeLabel! : "全天",
                        title: item.title,
                        note: item.note ?? "",
                        category: item.category?.isEmpty == false ? item.category! : "复习"
                    )
                }
            }
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !schedule.isEmpty else {
            throw ServiceError.invalidResponse
        }

        return schedule
    }

    func revisePlan(currentPlan: String, userRequest: String) async throws -> PlanRevision {
        let currentYear = Calendar.current.component(.year, from: Date())
        let today = DateKey.today()
        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是 CET-6 学习计划修改助理。根据用户的要求，改写当前计划书。
                    当前年份是 \(currentYear)，今天是 \(today)。
                    保留中文表达风格，日期必须写成“5月24日”这类真实日期，不要写“第几天”替代日期。
                    如果用户要求某件事在多个日期出现，请在每个日期都写清楚。
                    只输出 JSON，不要 Markdown，不要解释。
                    JSON 格式必须是：
                    {"reply":"简短说明你改了什么","planText":"完整新版计划书"}
                    """
                ),
                ChatMessage(
                    role: "user",
                    content: """
                    当前计划书：
                    \(currentPlan)

                    我的修改要求：
                    \(userRequest)
                    """
                )
            ],
            temperature: 0.35,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 2600,
            responseFormat: ResponseFormat(type: "json_object")
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(DeepSeekErrorResponse.self, from: data)
            throw ServiceError.requestFailed(apiError?.error.message ?? "DeepSeek 请求失败：HTTP \(httpResponse.statusCode)")
        }

        let completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content,
              let contentData = Self.cleanedJSONContent(content).data(using: .utf8) else {
            throw ServiceError.invalidResponse
        }

        let revision: PlanRevision
        do {
            revision = try decoder.decode(PlanRevision.self, from: contentData)
        } catch {
            throw ServiceError.requestFailed("DeepSeek 返回 JSON 格式不符合计划书结构：\(error.localizedDescription)")
        }
        guard !revision.planText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidResponse
        }

        return revision
    }

    func createStudyPlan(userProfile: String) async throws -> PlanRevision {
        let currentYear = Calendar.current.component(.year, from: Date())
        let today = DateKey.today()
        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是 CET-6 备考规划师。根据用户的备考情况，从零生成一份可执行的 CET-6 学习计划。
                    当前年份是 \(currentYear)，今天是 \(today)。
                    计划必须直接可被客户端拆成日程，所以每一行都要包含明确日期、时间段、任务标题和备注。
                    日期写成“6月2日”这类真实日期，不要写“第1天”替代日期。
                    任务要覆盖词汇、听力、阅读、翻译、写作、复习，按用户薄弱项倾斜。
                    每天任务量要现实，不要堆砌；如果用户没有给天数，默认生成未来 7 天。
                    只输出 JSON，不要 Markdown，不要解释。
                    JSON 格式必须是：
                    {"reply":"简短说明计划重点","planText":"完整计划书，每行一个任务，例如：6月2日 08:00-08:40 高频词 40 个，重点看同义替换"}
                    """
                ),
                ChatMessage(role: "user", content: userProfile)
            ],
            temperature: 0.35,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 3200,
            responseFormat: ResponseFormat(type: "json_object")
        )

        let contentData = try await performJSONRequest(requestBody, timeout: 60)
        let plan: PlanRevision
        do {
            plan = try decoder.decode(PlanRevision.self, from: contentData)
        } catch {
            throw ServiceError.requestFailed("DeepSeek 返回 JSON 格式不符合定计划结构：\(error.localizedDescription)")
        }

        guard !plan.planText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidResponse
        }

        return plan
    }

    func completeVocabularyWord(_ rawWord: String) async throws -> WordLookupResult {
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty else { throw ServiceError.invalidResponse }

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是 CET-6 单词本补全助手。根据用户输入的英文单词，补全适合六级备考的词条。
                    只输出 JSON，不要 Markdown，不要解释。
                    JSON 格式必须是：
                    {"word":"allocate","phonetic":"/ˈæləkeɪt/","partOfSpeech":"v.","meaning":"分配；拨出","example":"Students should allocate time for vocabulary review.","exampleTranslation":"学生应该分配时间进行词汇复习。","phrases":["allocate resources","allocate time to study"],"phraseTranslations":["分配资源","分配时间学习"],"mnemonic":"al- 去 + locate 放置：把资源放到合适位置就是分配","tag":"计划表达","difficulty":4}
                    要求：
                    1. word 使用小写英文原形或最常见词形。
                    2. phonetic 使用常见英式或美式音标，没有把握也要给出合理音标。
                    3. partOfSpeech 使用 n.、v.、adj.、adv. 等简洁词性。
                    4. meaning 用简洁中文，多个义项用中文分号隔开。
                    5. example 用一条自然英文例句，适合六级写作或阅读。
                    6. exampleTranslation 给 example 的自然中文翻译。
                    7. phrases 给 2 到 4 个常见短语或搭配。
                    8. phraseTranslations 与 phrases 一一对应，给每个短语的中文翻译。
                    9. mnemonic 用一句中文助记，优先词根词缀、形近联想或场景记忆。
                    10. tag 用 2 到 5 个中文，比如 阅读高频、写作替换、词根、听力高频、基础词。
                    11. difficulty 是 1 到 5 的整数。
                    """
                ),
                ChatMessage(role: "user", content: word)
            ],
            temperature: 0.25,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 500,
            responseFormat: ResponseFormat(type: "json_object")
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(DeepSeekErrorResponse.self, from: data)
            throw ServiceError.requestFailed(apiError?.error.message ?? "DeepSeek 请求失败：HTTP \(httpResponse.statusCode)")
        }

        let completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content,
              let contentData = Self.cleanedJSONContent(content).data(using: .utf8) else {
            throw ServiceError.invalidResponse
        }

        let result: WordLookupResult
        do {
            result = try decoder.decode(WordLookupResult.self, from: contentData)
        } catch {
            throw ServiceError.requestFailed("DeepSeek 返回 JSON 格式不符合单词结构：\(error.localizedDescription)")
        }

        guard !result.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidResponse
        }

        return result.normalized(fallbackWord: word)
    }

    func generateTranslationPractice(for rawInput: String) async throws -> TranslationPracticeResult {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw ServiceError.invalidResponse }

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是 CET-6 翻译题高分表达训练助手。用户可能输入中文句子，也可能输入英文句子。
                    如果输入是中文：给出 4 个适合六级翻译题的英文译法，从稳妥基础到高分升级，句型自然、准确、不过度炫技。
                    如果输入是英文：给出 4 个更适合六级写作/翻译的润色版本，保留原意，纠正语法并提升表达。
                    词汇和句型要符合六级水平，避免 GRE/学术论文式难词。
                    只输出 JSON，不要 Markdown，不要解释。
                    JSON 格式必须是：
                    {"mode":"中文翻译","title":"简短标题","versions":[{"label":"稳妥版","text":"英文句子","reason":"中文说明这个版本为什么适合六级"},{"label":"高分版","text":"英文句子","reason":"中文说明亮点"}],"notes":["易错点或表达提醒"]}
                    mode 只能是“中文翻译”或“英文润色”。
                    versions 必须有 3 到 5 个。
                    notes 给 2 到 4 条中文提醒。
                    """
                ),
                ChatMessage(role: "user", content: input)
            ],
            temperature: 0.45,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 1200,
            responseFormat: ResponseFormat(type: "json_object")
        )

        let contentData = try await performJSONRequest(requestBody, timeout: 45)
        let result: TranslationPracticeResult
        do {
            result = try decoder.decode(TranslationPracticeResult.self, from: contentData)
        } catch {
            throw ServiceError.requestFailed("DeepSeek 返回 JSON 格式不符合翻译训练结构：\(error.localizedDescription)")
        }

        guard !result.versions.isEmpty else { throw ServiceError.invalidResponse }
        return result.normalized(input: input)
    }

    func generateCET6Essay(for rawPrompt: String) async throws -> WritingPracticeResult {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw ServiceError.invalidResponse }

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是 CET-6 写作高分范文助手。根据用户输入的主题、句子或六级写作原题，生成一篇六级作文。
                    要求：
                    1. essay 必须是英文，150 到 200 词之间。
                    2. 内容符合六级写作评分标准：观点清楚、结构完整、衔接自然、语言准确。
                    3. 词汇和句型要有亮点，但不要太难，不要堆砌生僻词。
                    4. 注释要主动推断学习者可能不认识的词、短语、长难句，并用中文解释。
                    只输出 JSON，不要 Markdown，不要解释。
                    JSON 格式必须是：
                    {"title":"英文标题","essay":"完整英文作文","wordCount":168,"notes":[{"target":"单词/短语/句子","explanation":"中文解析"}],"usefulExpressions":["可迁移表达1","可迁移表达2"]}
                    notes 给 5 到 8 条。
                    usefulExpressions 给 3 到 6 条。
                    """
                ),
                ChatMessage(role: "user", content: prompt)
            ],
            temperature: 0.5,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 1800,
            responseFormat: ResponseFormat(type: "json_object")
        )

        let contentData = try await performJSONRequest(requestBody, timeout: 60)
        let result: WritingPracticeResult
        do {
            result = try decoder.decode(WritingPracticeResult.self, from: contentData)
        } catch {
            throw ServiceError.requestFailed("DeepSeek 返回 JSON 格式不符合写作训练结构：\(error.localizedDescription)")
        }

        guard !result.essay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.invalidResponse
        }

        return result.normalized(prompt: prompt)
    }

    func translateSelectionToChinese(_ rawText: String) async throws -> String {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ServiceError.invalidResponse }

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是 CET-6 阅读辅助翻译助手。把用户选中的英文短语或句子翻译成自然中文。
                    要求：
                    1. 只输出 JSON，不要 Markdown，不要解释。
                    2. 保留原意，翻译要适合六级学习者理解。
                    3. 如果是长句，可以在 translation 中直接给通顺中文，不要逐词硬译。
                    JSON 格式必须是：
                    {"translation":"自然中文翻译"}
                    """
                ),
                ChatMessage(role: "user", content: text)
            ],
            temperature: 0.2,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 500,
            responseFormat: ResponseFormat(type: "json_object")
        )

        let contentData = try await performJSONRequest(requestBody, timeout: 35)
        let result: SelectionTranslationResult
        do {
            result = try decoder.decode(SelectionTranslationResult.self, from: contentData)
        } catch {
            throw ServiceError.requestFailed("DeepSeek 返回 JSON 格式不符合选区翻译结构：\(error.localizedDescription)")
        }

        let translation = result.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { throw ServiceError.invalidResponse }
        return translation
    }

    private func performJSONRequest(_ requestBody: ChatCompletionRequest, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(DeepSeekErrorResponse.self, from: data)
            throw ServiceError.requestFailed(apiError?.error.message ?? "DeepSeek 请求失败：HTTP \(httpResponse.statusCode)")
        }

        let completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content,
              let contentData = Self.cleanedJSONContent(content).data(using: .utf8) else {
            throw ServiceError.invalidResponse
        }

        return contentData
    }

    private static func cleanedJSONContent(_ content: String) -> String {
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PlanRevision: Decodable {
    let reply: String
    let planText: String
}

struct WordLookupResult: Decodable {
    let word: String
    let phonetic: String
    let partOfSpeech: String
    let meaning: String
    let example: String
    let exampleTranslation: String
    let phrases: [String]
    let phraseTranslations: [String]
    let mnemonic: String
    let tag: String
    let difficulty: Int

    private enum CodingKeys: String, CodingKey {
        case word
        case phonetic
        case partOfSpeech
        case meaning
        case example
        case exampleTranslation
        case phrases
        case phraseTranslations
        case mnemonic
        case tag
        case difficulty
    }

    init(
        word: String,
        phonetic: String,
        partOfSpeech: String,
        meaning: String,
        example: String,
        exampleTranslation: String,
        phrases: [String],
        phraseTranslations: [String],
        mnemonic: String,
        tag: String,
        difficulty: Int
    ) {
        self.word = word
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.phrases = phrases
        self.phraseTranslations = phraseTranslations
        self.mnemonic = mnemonic
        self.tag = tag
        self.difficulty = difficulty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.word = try container.decodeIfPresent(String.self, forKey: .word) ?? ""
        self.phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        self.partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? "未标注"
        self.meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        self.example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        self.exampleTranslation = try container.decodeIfPresent(String.self, forKey: .exampleTranslation) ?? ""
        self.phrases = Self.decodeStringList(from: container, forKey: .phrases)
        self.phraseTranslations = Self.decodeStringList(from: container, forKey: .phraseTranslations)
        self.mnemonic = try container.decodeIfPresent(String.self, forKey: .mnemonic) ?? ""
        self.tag = Self.decodeStringOrList(from: container, forKey: .tag) ?? "自定义"
        self.difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 3
    }

    func normalized(fallbackWord: String) -> WordLookupResult {
        WordLookupResult(
            word: word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackWord : word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            phonetic: phonetic.trimmingCharacters(in: .whitespacesAndNewlines),
            partOfSpeech: partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未标注" : partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines),
            meaning: meaning.trimmingCharacters(in: .whitespacesAndNewlines),
            example: example.trimmingCharacters(in: .whitespacesAndNewlines),
            exampleTranslation: exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
            phrases: phrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            phraseTranslations: phraseTranslations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            mnemonic: mnemonic.trimmingCharacters(in: .whitespacesAndNewlines),
            tag: tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "自定义" : tag.trimmingCharacters(in: .whitespacesAndNewlines),
            difficulty: min(max(difficulty, 1), 5)
        )
    }

    private static func decodeStringList(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [String] {
        if let strings = try? container.decodeIfPresent([String].self, forKey: key) {
            return strings
        }
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return string
                .components(separatedBy: CharacterSet(charactersIn: "；;、,，"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private static func decodeStringOrList(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return string
        }
        if let strings = try? container.decodeIfPresent([String].self, forKey: key) {
            return strings.joined(separator: "、")
        }
        return nil
    }
}

struct TranslationPracticeResult: Codable, Equatable {
    let input: String
    let mode: String
    let title: String
    let versions: [TranslationVersion]
    let notes: [String]

    init(input: String = "", mode: String, title: String, versions: [TranslationVersion], notes: [String]) {
        self.input = input
        self.mode = mode
        self.title = title
        self.versions = versions
        self.notes = notes
    }

    func normalized(input: String) -> TranslationPracticeResult {
        TranslationPracticeResult(
            input: input,
            mode: mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "中文翻译" : mode.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(input.prefix(18)) : title.trimmingCharacters(in: .whitespacesAndNewlines),
            versions: versions.map(\.normalized).filter { !$0.text.isEmpty },
            notes: notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
    }
}

struct TranslationVersion: Codable, Equatable, Identifiable {
    var id: String { label + text }
    let label: String
    let text: String
    let reason: String

    var normalized: TranslationVersion {
        TranslationVersion(
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "表达版本" : label.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct WritingPracticeResult: Codable, Equatable {
    let prompt: String
    let title: String
    let essay: String
    let wordCount: Int
    let notes: [WritingPracticeNote]
    let usefulExpressions: [String]

    private enum CodingKeys: String, CodingKey {
        case prompt
        case title
        case essay
        case wordCount
        case notes
        case usefulExpressions
    }

    init(prompt: String = "", title: String, essay: String, wordCount: Int, notes: [WritingPracticeNote], usefulExpressions: [String]) {
        self.prompt = prompt
        self.title = title
        self.essay = essay
        self.wordCount = wordCount
        self.notes = notes
        self.usefulExpressions = usefulExpressions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "CET-6 Essay"
        self.essay = try container.decodeIfPresent(String.self, forKey: .essay) ?? ""
        self.wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0
        self.notes = try container.decodeIfPresent([WritingPracticeNote].self, forKey: .notes) ?? []
        self.usefulExpressions = try container.decodeIfPresent([String].self, forKey: .usefulExpressions) ?? []
    }

    func normalized(prompt: String) -> WritingPracticeResult {
        let cleanedEssay = essay.trimmingCharacters(in: .whitespacesAndNewlines)
        return WritingPracticeResult(
            prompt: prompt,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "CET-6 Essay" : title.trimmingCharacters(in: .whitespacesAndNewlines),
            essay: cleanedEssay,
            wordCount: wordCount > 0 ? wordCount : Self.countWords(in: cleanedEssay),
            notes: notes.map(\.normalized).filter { !$0.target.isEmpty || !$0.explanation.isEmpty },
            usefulExpressions: usefulExpressions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
    }

    private static func countWords(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.count
    }
}

struct WritingPracticeNote: Codable, Equatable, Identifiable {
    var id: String { target + explanation }
    let target: String
    let explanation: String

    private enum CodingKeys: String, CodingKey {
        case target
        case explanation
    }

    init(target: String, explanation: String) {
        self.target = target
        self.explanation = explanation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
        self.explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
    }

    var normalized: WritingPracticeNote {
        WritingPracticeNote(
            target: target.trimmingCharacters(in: .whitespacesAndNewlines),
            explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct SelectionTranslationResult: Decodable {
    let translation: String
}

enum EnvLoader {
    static func load() -> [String: String] {
        var values = ProcessInfo.processInfo.environment

        for fileURL in candidateFileURLs() where FileManager.default.fileExists(atPath: fileURL.path) {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            parse(content).forEach { key, value in
                if values[key]?.isEmpty ?? true {
                    values[key] = value
                }
            }
        }

        return values
    }

    private static func candidateFileURLs() -> [URL] {
        let projectURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("CET-6", isDirectory: true)
            .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)
            .appendingPathComponent(".env")

        let workingDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".env")

        return [workingDirectoryURL, projectURL]
    }

    private static func parse(_ content: String) -> [String: String] {
        var values: [String: String] = [:]

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }

            if !key.isEmpty {
                values[key] = value
            }
        }

        return values
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let thinking: ThinkingMode
    let maxTokens: Int
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case thinking
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ThinkingMode: Encodable {
    let type: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct DeepSeekErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

private struct GeneratedSchedule: Decodable {
    let schedule: [GeneratedScheduleItem]
}

private struct GeneratedScheduleItem: Decodable {
    let dateKeys: [String]?
    let dateKey: String?
    let timeLabel: String?
    let title: String
    let note: String?
    let category: String?

    func normalizedDateKeys() -> [String] {
        let keys = dateKeys ?? dateKey.map { [$0] } ?? [DateKey.today()]
        return keys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { DateKey.normalized($0) ?? $0 }
            .filter { !$0.isEmpty }
    }
}
