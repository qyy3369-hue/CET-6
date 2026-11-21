import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

struct MarkedVocabularyImage: Sendable {
    enum Input: Sendable {
        case file(URL)
        case data(Data)
    }

    enum ImageError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "无法读取这张图片，请试试 PNG、JPEG 或 HEIC 截图。"
        }
    }

    struct Word: Sendable {
        let text: String
        let bounds: CGRect
        let isMarked: Bool
    }

    let image: CGImage
    let words: [Word]

    static func load(_ input: Input) throws -> CGImage {
        let source: CGImageSource?
        switch input {
        case .file(let url):
            guard url.isFileURL else { throw ImageError.unreadable }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw ImageError.unreadable
            }
            return try thumbnail(from: source)
        case .data(let data):
            source = CGImageSourceCreateWithData(data as CFData, nil)
        }
        guard let source else { throw ImageError.unreadable }
        return try thumbnail(from: source)
    }

    private static func thumbnail(from source: CGImageSource) throws -> CGImage {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2600
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw ImageError.unreadable
        }
        return image
    }

    static func recognize(_ image: CGImage) throws -> Self {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = false
        // Avoid the per-process Neural Engine compilation delay on the first screenshot.
        for (stage, devices) in (try? request.supportedComputeStageDevices) ?? [:] {
            if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()

        let marks = try ImageInk.marks(in: image)
        let scale = CGSize(width: image.width, height: image.height)
        let matches = try NSRegularExpression(
            pattern: #"https?://\S+|[A-Za-z0-9]+(?:['’.\-][A-Za-z0-9]+)*"#,
            options: .caseInsensitive
        )
        let words = (request.results ?? []).flatMap { observation -> [Word] in
            guard let candidate = observation.topCandidates(1).first else { return [] }
            let line = candidate.string
            return matches.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
                guard let range = Range(match.range, in: line),
                      let text = cleanWord(String(line[range])),
                      let box = try? candidate.boundingBox(for: range)?.boundingBox,
                      !box.isEmpty else { return nil }
                let bounds = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                let pixels = CGRect(
                    x: bounds.minX * scale.width, y: bounds.minY * scale.height,
                    width: bounds.width * scale.width, height: bounds.height * scale.height
                )
                return Word(text: text, bounds: bounds, isMarked: marks.contains { $0.contains(pixels) })
            }
        }
        return Self(image: image, words: words)
    }

    static func cleanWord(_ raw: String) -> String? {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
        guard (2...64).contains(word.count),
              word.range(of: #"^[a-z]+(?:['-][a-z]+)*$"#, options: .regularExpression) != nil else { return nil }
        return word
    }

    static func pngData(_ image: CGImage) throws -> Data {
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageError.unreadable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.unreadable }
        return bytes as Data
    }
}

private enum ImageInk {
    struct Mark {
        enum Kind { case outline, underline, highlight }

        let bounds: CGRect
        let kinds: [Kind]

        func contains(_ word: CGRect) -> Bool {
            let widthOverlap = max(0, min(bounds.maxX, word.maxX) - max(bounds.minX, word.minX))
            let horizontalCover = widthOverlap / word.width
            return kinds.contains { kind in
                switch kind {
                case .outline:
                    return horizontalCover >= 0.78
                        && bounds.contains(CGPoint(x: word.midX, y: word.midY))
                        && bounds.height >= word.height * 1.17
                        && bounds.width >= word.width * 1.02
                case .underline:
                    let gap = bounds.midY - word.maxY
                    return horizontalCover >= 0.55 && gap >= -word.height * 0.22
                        && gap <= max(5, word.height * 0.66)
                case .highlight:
                    let overlap = bounds.intersection(word)
                    return horizontalCover >= 0.56 && !overlap.isNull
                        && overlap.height >= word.height * 0.36
                        && bounds.height <= max(12, word.height * 2.6)
                }
            }
        }
    }

    static func marks(in image: CGImage) throws -> [Mark] {
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let mask: [UInt8]? = rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = bytes.bindMemory(to: UInt8.self)
            var brightSamples = 0
            var samples = 0
            for index in stride(from: 0, to: width * height, by: 101) {
                if pixels[index * 4 + 1] > 145 { brightSamples += 1 }
                samples += 1
            }
            let lightPage = brightSamples * 2 >= samples
            var values = [UInt8](repeating: 0, count: width * height)
            for index in values.indices {
                let offset = 4 * index
                values[index] = inkClass(
                    red: Int(pixels[offset]), green: Int(pixels[offset + 1]), blue: Int(pixels[offset + 2]),
                    lightPage: lightPage
                )
            }
            return values
        }
        guard var mask else { throw MarkedVocabularyImage.ImageError.unreadable }
        return try components(in: &mask, width: width, height: height)
    }

    // Neighboring tones stay connected across the antialiased edges of a mark.
    private static func inkClass(red: Int, green: Int, blue: Int, lightPage: Bool) -> UInt8 {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let chroma = maximum - minimum
        guard maximum >= 76, chroma >= max(28, maximum / 8) else {
            return (lightPage ? maximum <= 34 : minimum >= 222) ? 7 : 0
        }
        if red == maximum { return green - blue > chroma / 3 ? 2 : (blue - green > chroma / 2 ? 6 : 1) }
        if green == maximum { return blue - red > chroma / 3 ? 4 : (red - blue > chroma / 2 ? 2 : 3) }
        return red - green > chroma / 3 ? 6 : (green - red > chroma / 2 ? 4 : 5)
    }

    private static func components(in mask: inout [UInt8], width: Int, height: Int) throws -> [Mark] {
        var marks: [Mark] = []
        var points: [Int32] = []
        for start in mask.indices {
            if start.isMultiple(of: 65_536) { try Task.checkCancellation() }
            let ink = mask[start]
            guard ink != 0 else { continue }
            points.removeAll(keepingCapacity: true)
            points.append(Int32(start))
            mask[start] = 0
            var index = 0
            var minX = start % width
            var maxX = minX
            var minY = start / width
            var maxY = minY
            while index < points.count {
                let point = Int(points[index])
                let x = point % width
                let y = point / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                if x > 0, mask[point - 1] == ink { mask[point - 1] = 0; points.append(Int32(point - 1)) }
                if x + 1 < width, mask[point + 1] == ink { mask[point + 1] = 0; points.append(Int32(point + 1)) }
                if y > 0, mask[point - width] == ink { mask[point - width] = 0; points.append(Int32(point - width)) }
                if y + 1 < height, mask[point + width] == ink { mask[point + width] = 0; points.append(Int32(point + width)) }
                index += 1
            }
            let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            guard points.count >= 18, bounds.width >= 10,
                  bounds.width < Double(width) * 0.96, bounds.height < Double(height) * 0.97 else { continue }
            let kinds = classify(points, bounds: bounds, width: width, colored: ink != 7)
            if !kinds.isEmpty { marks.append(Mark(bounds: bounds, kinds: kinds)) }
            if ink == 7, !kinds.contains(.underline),
               let line = attachedUnderline(points, bounds: bounds, width: width) {
                marks.append(Mark(bounds: line, kinds: [.underline]))
            }
        }
        return marks
    }

    private static func attachedUnderline(_ points: [Int32], bounds: CGRect, width: Int) -> CGRect? {
        guard bounds.width >= 20, bounds.height >= 8, bounds.width >= bounds.height * 1.15 else { return nil }
        let firstRow = Int(bounds.maxY) - 7
        var rows = [(count: Int, left: Int, right: Int)](repeating: (0, Int.max, 0), count: 7)
        for point in points where Int(point) / width >= firstRow {
            let row = Int(point) / width - firstRow
            let x = Int(point) % width
            rows[row].count += 1
            rows[row].left = min(rows[row].left, x)
            rows[row].right = max(rows[row].right, x)
        }
        for (index, row) in rows.dropLast().enumerated() where Double(row.count) >= bounds.width * 0.78 {
            let next = rows[index + 1]
            let left = max(row.left, next.left)
            let right = min(row.right, next.right)
            if Double(next.count) >= bounds.width * 0.78, Double(right - left + 1) >= bounds.width * 0.75 {
                return CGRect(x: left, y: firstRow + index, width: right - left + 1, height: 2)
            }
        }
        return nil
    }

    private static func classify(
        _ points: [Int32], bounds: CGRect, width: Int, colored: Bool
    ) -> [Mark.Kind] {
        let w = bounds.width
        let h = bounds.height
        let fill = Double(points.count) / (w * h)
        var kinds: [Mark.Kind] = []
        if w >= 13, h <= w / 2.75, fill >= 0.38,
           colored || (h >= 2 && Double(points.count) / w >= 1.9) {
            kinds.append(.underline)
        }
        if colored, h >= 7, w >= h * 0.7, fill >= 0.53 {
            kinds.append(.highlight)
        }

        guard h >= 12, w >= 14, fill < 0.55,
              colored || Double(points.count) / (2 * (w + h)) >= 1.65 else { return kinds }
        var top = 0
        var bottom = 0
        var left = 0
        var right = 0
        var middle = 0
        for point in points {
            let x = (Double(Int(point) % width) - bounds.minX) / w
            let y = (Double(Int(point) / width) - bounds.minY) / h
            if x > 0.22, x < 0.78 {
                if y < 0.24 { top += 1 }
                if y > 0.76 { bottom += 1 }
                if y > 0.3, y < 0.7, x > 0.3, x < 0.7 { middle += 1 }
            }
            if y > 0.22, y < 0.78 {
                if x < 0.24 { left += 1 }
                if x > 0.76 { right += 1 }
            }
        }
        if Double(min(top, bottom)) >= w * 0.23,
           Double(min(left, right)) >= h * 0.23,
           Double(middle) < w * h * 0.04 {
            kinds.append(.outline)
        }
        return kinds
    }
}
