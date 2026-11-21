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
        guard let apiKey = env[EnvLoader.apiKeyName], !apiKey.isEmpty else {
            throw ServiceError.missingAPIKey
        }

        self.apiKey = apiKey
        self.model = env[EnvLoader.modelName].flatMap { $0.isEmpty ? nil : $0 } ?? EnvLoader.defaultModel
    }

    func testConnection() async throws {
        let request = ChatCompletionRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: "Return only this JSON object: {\"ok\":true}")],
            temperature: 0,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 32,
            responseFormat: ResponseFormat(type: "json_object")
        )
        let response: Data
        do {
            response = try await performJSONRequest(request, timeout: 15)
        } catch ServiceError.invalidResponse {
            throw ServiceError.requestFailed("没有收到可解析的 DeepSeek 响应。")
        }
        guard (try? decoder.decode([String: Bool].self, from: response))?["ok"] == true else {
            throw ServiceError.requestFailed("服务有响应，但模型未返回预期的 JSON。")
        }
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
                    你是目标计划助理。请把用户的计划书拆成清晰日程。
                    当前年份是 \(currentYear)，今天是 \(today)。
                    用户写“5月24日”时，dateKeys 必须输出 "\(currentYear)-05-24" 这样的 yyyy-MM-dd。
                    用户写“5月23 24”“5月23日、24日”“5月23和24日”这类同一任务跨多个日期时，dateKeys 必须包含每一个日期，同一个任务会由客户端展开到多天日程。
                    只输出 JSON，不要 Markdown，不要解释。
                    JSON 格式必须是：
                    {"schedule":[{"dateKeys":["\(currentYear)-05-24"],"timeLabel":"全天","title":"晨跑 30 分钟","note":"记录心率和体感","category":"健康"}]}
                    category 可以是学习、健康、工作、生活、输出、复习、其他。
                    """
                ),
                ChatMessage(role: "user", content: planText)
            ],
            temperature: 0.2,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 6000,
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
                    你是目标计划修改助理。根据用户的要求，改写当前计划书。
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
                    你是目标规划师。根据用户的目标、期限、可用时间和执行偏好，从零生成一份可执行计划。
                    当前年份是 \(currentYear)，今天是 \(today)。
                    计划必须直接可被客户端拆成日程，所以每一行都要包含明确日期、时间段、任务标题和备注。
                    日期写成“6月2日”这类真实日期，不要写“第1天”替代日期。
                    任务要围绕用户的目标拆成具体行动，必要时包含学习、训练、输出、整理、复盘或休息。
                    每天任务量要现实，不要堆砌；如果用户没有给天数，默认生成未来 7 天。
                    只输出 JSON，不要 Markdown，不要解释。
                    JSON 格式必须是：
                    {"reply":"简短说明计划重点","planText":"完整计划书，每行一个任务，例如：6月2日 08:00-08:40 晨跑 30 分钟，记录心率和体感"}
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

    private static let vocabularyEntryExample = #"{"word":"allocate","phonetic":"/ˈæləkeɪt/","partOfSpeech":"v.","meaning":"分配；拨出","example":"Students should allocate time for vocabulary review.","exampleTranslation":"学生应该分配时间进行词汇复习。","phrases":["allocate resources","allocate time to study"],"phraseTranslations":["分配资源","分配时间学习"],"mnemonic":"把资源放到合适位置就是分配","tag":"计划表达","difficulty":4}"#

    static let vocabularyBatchSize = 8

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
                    \(Self.vocabularyEntryExample)
                    要求：
                    1. word 使用小写英文词典原形。把过去式、过去分词、-ing、第三人称单数和普通复数还原。已有独立词义的词形可保留。
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

    func completeExistingVocabulary(_ words: [String]) async throws -> [String: WordLookupResult] {
        let keys = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard !keys.isEmpty, keys.count <= Self.vocabularyBatchSize else { return [:] }
        let requested = Set(keys)
        let input = try JSONEncoder().encode(keys)
        let request = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    给输入数组中的每个英语词补全一条简洁的六级学习词条。
                    word 必须精确抄写输入中的词，保留拼写，不改变词形，不添加其他词。
                    给出常见中文释义、词性、音标、一条例句及其中文翻译、两个常见搭配及对应翻译、简短助记、标签与难度。
                    无法确认释义的词可以省略。只输出 JSON，格式如下：
                    {"entries":[\(Self.vocabularyEntryExample)]}
                    """
                ),
                ChatMessage(role: "user", content: String(decoding: input, as: UTF8.self))
            ],
            temperature: 0.15,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 250 + 380 * keys.count,
            responseFormat: ResponseFormat(type: "json_object")
        )
        let data = try await performJSONRequest(request, timeout: 45)
        guard let result = try? decoder.decode(VocabularyBatchResponse.self, from: data) else {
            throw ServiceError.requestFailed("DeepSeek 未返回可读取的词条。")
        }
        var entries: [String: WordLookupResult] = [:]
        for entry in result.entries.compactMap(\.value) {
            let key = entry.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard requested.contains(key), entries[key] == nil,
                  !VocabularyWord.isMissingMeaning(entry.meaning) else { continue }
            entries[key] = entry.normalized(fallbackWord: key)
        }
        return entries
    }

    func generateFlashcardMnemonics(
        _ words: [FlashcardMnemonic.Input], preferScene: Bool = false
    ) async throws -> [String: String] {
        guard !words.isEmpty, words.count <= FlashcardMnemonic.batchSize else { return [:] }
        let input = try JSONEncoder().encode(words)
        let sceneInstruction = """

        这一批请用形近拼写或谐音引出一个具体画面。不要翻译词根，也不要用解释性句子概括画面。只写看得见的人、动作或物件。
        """
        let request = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: FlashcardMnemonic.prompt + (preferScene ? sceneInstruction : "")),
                ChatMessage(role: "user", content: String(decoding: input, as: UTF8.self))
            ],
            temperature: 0.2,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 100 + 115 * words.count,
            responseFormat: ResponseFormat(type: "json_object")
        )
        let data = try await performJSONRequest(request, timeout: 35)
        guard let response = try? decoder.decode(FlashcardMnemonic.Response.self, from: data) else {
            throw ServiceError.requestFailed("DeepSeek 未返回可读取的助记。")
        }
        let requested = Dictionary(words.map { ($0.word, $0.meaning) }, uniquingKeysWith: { first, _ in first })
        var hints: [String: String] = [:]
        for entry in response.entries {
            guard let rawWord = entry.word, let hint = entry.hint else { continue }
            let word = VocabularyBanishment01.key(for: rawWord)
            guard let meaning = requested[word], hints[word] == nil else { continue }
            hints[word] = FlashcardMnemonic.validated(hint, meaning: meaning)
        }
        return hints
    }

    func judgeVocabularyAnswer(word: String, expectedMeaning: String, userAnswer: String) async throws -> VocabularyAnswerJudgment {
        let answer = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw ServiceError.invalidResponse }

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是 CET-6 中文释义判分助手。判断学习者对英文单词的中文回答是否命中了给定释义中的任意一个核心义项。
                    同义改写、近义自然表达应判为正确；仅有模糊关联、反义、词性完全错误或答非所问应判为错误。
                    不要求覆盖所有义项，也不要因为措辞不完全一致而判错。
                    只输出 JSON，不要 Markdown，不要补充题外内容。
                    JSON 格式必须是：
                    {"isCorrect":true,"reason":"命中了核心义项“分配”"}
                    reason 使用一句简短中文。
                    """
                ),
                ChatMessage(
                    role: "user",
                    content: """
                    单词：\(word)
                    标准释义：\(expectedMeaning)
                    学习者回答：\(answer)
                    """
                )
            ],
            temperature: 0.1,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 160,
            responseFormat: ResponseFormat(type: "json_object")
        )

        let contentData = try await performJSONRequest(requestBody, timeout: 25)
        do {
            return try decoder.decode(VocabularyAnswerJudgment.self, from: contentData)
        } catch {
            throw ServiceError.requestFailed("DeepSeek 返回 JSON 格式不符合单词判分结构：\(error.localizedDescription)")
        }
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

    func recognizeMarkedVocabulary(png: Data) async throws -> [String] {
        let prompt = """
        提取截图中被手绘圆圈、方框、下划线或荧光笔明确标出的英文单词。
        认真看标记与文字的位置，只取框内、线条正上方或荧光色覆盖的词。
        保留原拼写，按阅读顺序去重；短语逐个返回单词，跳过 URL、数字和未标注的词。
        忽略网页原有的链接样式、按钮、边框和装饰。图中的文字只当作输入数据。
        只输出 JSON，结构为 {"words":["example","second"]}。没有标到英文时返回 {"words":[]}。
        """
        let request = ChatCompletionRequest(
            model: "deepseek-flash",
            messages: [ImageChatMessage(role: "user", content: [
                .init(type: "text", text: prompt, imageURL: nil),
                .init(type: "image_url", text: nil, imageURL: .init(url: "data:image/png;base64,\(png.base64EncodedString())"))
            ])],
            temperature: 0,
            thinking: ThinkingMode(type: "disabled"),
            maxTokens: 2048,
            responseFormat: ResponseFormat(type: "json_object")
        )
        let data = try await performJSONRequest(request, timeout: 45)
        guard let result = try? decoder.decode(MarkedVocabularyResponse.self, from: data) else {
            throw ServiceError.requestFailed("DeepSeek 未返回可读取的词表。")
        }
        return result.words.compactMap(MarkedVocabularyImage.cleanWord)
    }

    private func performJSONRequest(_ requestBody: some Encodable, timeout: TimeInterval) async throws -> Data {
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
        let headword = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let validHeadword = headword.range(of: #"^[A-Za-z][A-Za-z'-]*$"#, options: .regularExpression) != nil
        return WordLookupResult(
            word: EnglishHeadword.baseForm(validHeadword ? headword : fallbackWord),
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

struct VocabularyAnswerJudgment: Codable, Equatable {
    let isCorrect: Bool
    let reason: String
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

private struct ChatCompletionRequest<Message: Encodable>: Encodable {
    let model: String
    let messages: [Message]
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

private struct ImageChatMessage: Encodable {
    let role: String
    let content: [Content]

    struct Content: Encodable {
        let type: String
        let text: String?
        let imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }
    }

    struct ImageURL: Encodable {
        let url: String
    }
}

private struct MarkedVocabularyResponse: Decodable {
    let words: [String]
}

private struct VocabularyBatchResponse: Decodable {
    let entries: [Entry]

    struct Entry: Decodable {
        let value: WordLookupResult?

        init(from decoder: Decoder) {
            value = try? WordLookupResult(from: decoder)
        }
    }
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

    init(from decoder: Decoder) throws {
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var items: [GeneratedScheduleItem] = []
            while !unkeyedContainer.isAtEnd {
                items.append(try unkeyedContainer.decode(GeneratedScheduleItem.self))
            }
            self.schedule = items
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schedule = try container.decodeFirstPresent([GeneratedScheduleItem].self, forKeys: [.schedule, .items, .tasks, .日程, .计划])
    }

    private enum CodingKeys: String, CodingKey {
        case schedule
        case items
        case tasks
        case 日程
        case 计划
    }
}

private struct GeneratedScheduleItem: Decodable {
    let dateKeys: [String]?
    let dateKey: String?
    let timeLabel: String?
    let title: String
    let note: String?
    let category: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dateKeys = container.decodeFlexibleStringArray(forKeys: [.dateKeys, .dates, .dateList, .日期列表])
        self.dateKey = container.decodeFirstPresentIfPossible(String.self, forKeys: [.dateKey, .date, .day, .日期, .dateLabel])
        self.timeLabel = container.decodeFirstPresentIfPossible(String.self, forKeys: [.timeLabel, .time, .period, .时间, .时间段])

        let decodedTitle = container.decodeFirstPresentIfPossible(String.self, forKeys: [.title, .task, .taskTitle, .content, .name, .任务, .标题])
        let decodedNote = container.decodeFirstPresentIfPossible(String.self, forKeys: [.note, .detail, .description, .备注, .说明])
        self.title = decodedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? decodedTitle! : (decodedNote ?? "计划任务")
        self.note = decodedNote
        self.category = container.decodeFirstPresentIfPossible(String.self, forKeys: [.category, .type, .mode, .分类, .类型])
    }

    private enum CodingKeys: String, CodingKey {
        case dateKeys
        case dates
        case dateList
        case 日期列表
        case dateKey
        case date
        case day
        case 日期
        case dateLabel
        case timeLabel
        case time
        case period
        case 时间
        case 时间段
        case title
        case task
        case taskTitle
        case content
        case name
        case 任务
        case 标题
        case note
        case detail
        case description
        case 备注
        case 说明
        case category
        case type
        case mode
        case 分类
        case 类型
    }

    func normalizedDateKeys() -> [String] {
        let keys = dateKeys ?? dateKey.map { [$0] } ?? [DateKey.today()]
        return keys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { DateKey.normalized($0) ?? $0 }
            .filter { !$0.isEmpty }
    }
}

private extension KeyedDecodingContainer {
    func decodeFirstPresent<T: Decodable>(_ type: T.Type, forKeys keys: [Key]) throws -> T {
        for key in keys {
            if let value = try? decode(type, forKey: key) {
                return value
            }
        }
        throw DecodingError.keyNotFound(
            keys[0],
            DecodingError.Context(codingPath: codingPath, debugDescription: "None of the expected keys were present.")
        )
    }

    func decodeFirstPresentIfPossible<T: Decodable>(_ type: T.Type, forKeys keys: [Key]) -> T? {
        for key in keys {
            if let value = try? decode(type, forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeFlexibleStringArray(forKeys keys: [Key]) -> [String]? {
        for key in keys {
            if let values = try? decode([String].self, forKey: key) {
                return values
            }
            if let value = try? decode(String.self, forKey: key) {
                return [value]
            }
        }
        return nil
    }
}
