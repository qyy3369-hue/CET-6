import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageVocabularyImportView: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: ([String]) -> Void

    @State private var image: CGImage?
    @State private var detected: [MarkedVocabularyImage.Word] = []
    @State private var suggested: [String] = []
    @State private var selected: Set<String> = []
    @State private var showAll = false
    @State private var dragOver = false
    @State private var choosingFile = false
    @State private var usingCloud = false
    @State private var work: Task<Void, Never>?
    @State private var message: String?

    private var visibleWords: [String] {
        Self.unique(suggested + (showAll ? detected.map(\.text) : []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("图片导词")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("选取图片", systemImage: "folder") { choosingFile = true }
                    .buttonStyle(GoalsButtonStyle())
                Button("粘贴图片", systemImage: "clipboard", action: pasteImage)
                    .buttonStyle(GoalsButtonStyle())
                    .keyboardShortcut("v", modifiers: .command)
            }

            HStack(spacing: 14) {
                preview
                    .frame(width: 455, height: 380)

                results
                    .frame(width: 250, height: 380)
            }

            HStack {
                if image != nil {
                    Button("DeepSeek 重识别", systemImage: "sparkles", action: retryWithDeepSeek)
                        .buttonStyle(GoalsButtonStyle())
                        .disabled(usingCloud && work != nil)
                    Text("上传当前图片，按用量计费")
                        .font(.caption)
                        .foregroundStyle(StudyTheme.secondaryInk)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(GoalsButtonStyle())
                Button("加入 \(selected.count) 个单词") {
                    onImport(visibleWords.filter(selected.contains))
                    dismiss()
                }
                .buttonStyle(GoalsButtonStyle(.primary))
                .disabled(selected.isEmpty || work != nil)
            }
        }
        .padding(22)
        .background(StudyTheme.windowBase)
        .foregroundStyle(StudyTheme.ink)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): openImage { .file(url) }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .onDisappear { work?.cancel() }
    }

    private var preview: some View {
        ZStack {
            if let image {
                GeometryReader { geometry in
                    let fit = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
                    let size = CGSize(width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .overlay {
                            Canvas { context, size in
                                for word in detected where selected.contains(word.text) && (word.isMarked || showAll) {
                                    let box = word.bounds
                                    let rect = CGRect(
                                        x: box.minX * size.width, y: box.minY * size.height,
                                        width: box.width * size.width, height: box.height * size.height
                                    ).insetBy(dx: -1, dy: -1)
                                    context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(.blue), lineWidth: 1.25)
                                }
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(10)
                .accessibilityLabel("待导入图片预览")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(StudyTheme.blue)
                        .accessibilityHidden(true)
                    Text("将图片拖到这里")
                        .font(.headline)
                    Text("支持圈选、方框、下划线和荧光笔")
                        .foregroundStyle(StudyTheme.secondaryInk)
                        .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dragOver ? StudyTheme.selection : StudyTheme.field, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(dragOver ? StudyTheme.blue : StudyTheme.hairline, style: StrokeStyle(lineWidth: 1, dash: image == nil ? [5, 4] : []))
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dragOver, perform: receiveDrop)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("识别结果").font(.headline)
                Spacer()
                Text("已选 \(selected.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(StudyTheme.secondaryInk)
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(StudyTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if work != nil {
                ProgressView(usingCloud ? "DeepSeek 正在识图…" : "正在本地识别…")
                    .controlSize(.small)
            }

            if !visibleWords.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(visibleWords, id: \.self) { word in
                            Toggle(word, isOn: Binding(
                                get: { selected.contains(word) },
                                set: { if $0 { selected.insert(word) } else { selected.remove(word) } }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
            if !detected.isEmpty, detected.contains(where: { !$0.isMarked }) {
                Toggle("查看整页识别词", isOn: $showAll)
                    .toggleStyle(.checkbox)
                    .disabled(work != nil)
                    .onChange(of: showAll) { _, isShowingAll in
                        if !isShowingAll { selected.formIntersection(suggested) }
                    }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StudyTheme.paper, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(StudyTheme.hairline).allowsHitTesting(false) }
    }

    private func pasteImage() {
        let pasteboard = NSPasteboard.general
        // Finder can provide both a file URL and a TIFF preview of its file icon.
        if let url = pasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true])?.first as? URL {
            openImage { .file(url) }
        } else if let data = pasteboard.pasteboardItems?.lazy.compactMap({ item in
            item.types.lazy.filter { UTType($0.rawValue)?.conforms(to: .image) == true }
                .compactMap { item.data(forType: $0) }.first
        }).first {
            openImage { .data(data) }
        } else {
            message = "剪贴板里没有图片或图片文件。"
        }
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              let type = Self.dropType(for: provider) else { return false }

        let representations = AsyncThrowingStream<Data, Error> { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data {
                    continuation.yield(data)
                    continuation.finish()
                } else {
                    continuation.finish(throwing: error ?? MarkedVocabularyImage.ImageError.unreadable)
                }
            }
        }
        openImage {
            var iterator = representations.makeAsyncIterator()
            guard let data = try await iterator.next() else {
                throw MarkedVocabularyImage.ImageError.unreadable
            }
            if type == UTType.fileURL.identifier,
               let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                return .file(url)
            }
            return .data(data)
        }
        return true
    }

    private static func dropType(for provider: NSItemProvider) -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return UTType.fileURL.identifier
        }
        let images = provider.registeredTypeIdentifiers.filter { UTType($0)?.conforms(to: .image) == true }
        return images.first { $0 != UTType.image.identifier } ?? images.first
    }

    private func openImage(_ input: @escaping @Sendable () async throws -> MarkedVocabularyImage.Input) {
        work?.cancel()
        image = nil
        detected = []
        suggested = []
        selected = []
        showAll = false
        usingCloud = false
        message = nil

        work = Task {
            defer { if !Task.isCancelled { work = nil } }
            do {
                let source = try await input()
                let decoded = try await Self.inBackground { try MarkedVocabularyImage.load(source) }
                try Task.checkCancellation()
                image = decoded
                let result = try await Self.inBackground { try MarkedVocabularyImage.recognize(decoded) }
                try Task.checkCancellation()
                detected = result.words
                updateSuggestions(result.words.filter(\.isMarked).map(\.text))
                if suggested.isEmpty {
                    message = detected.isEmpty ? "没有读到英文单词。" : "没有找到明确标记。可查看整页识别词，或用 DeepSeek 重识别。"
                }
            } catch {
                if !Task.isCancelled { message = "识别失败。\(error.localizedDescription)" }
            }
        }
    }

    private func retryWithDeepSeek() {
        guard let image, !usingCloud || work == nil else { return }
        work?.cancel()
        usingCloud = true
        message = nil
        work = Task {
            defer { if !Task.isCancelled { work = nil } }
            do {
                let png = try await Self.inBackground { try MarkedVocabularyImage.pngData(image) }
                try Task.checkCancellation()
                let words = try await DeepSeekPlanService().recognizeMarkedVocabulary(png: png)
                try Task.checkCancellation()
                if words.isEmpty {
                    message = "DeepSeek 没有找到被标记的英文。"
                } else {
                    updateSuggestions(words)
                }
            } catch {
                if !Task.isCancelled { message = "DeepSeek 识别失败。\(error.localizedDescription)" }
            }
        }
    }

    private func updateSuggestions(_ words: [String]) {
        suggested = Self.unique(words)
        selected = Set(suggested)
    }

    private static func unique(_ words: [String]) -> [String] {
        var seen: Set<String> = []
        return words.filter { seen.insert($0).inserted }
    }

    private static func inBackground<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let job = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler {
            try await job.value
        } onCancel: {
            job.cancel()
        }
    }
}
