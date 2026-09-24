public import UniformTypeIdentifiers

public enum FileKind: String, Sendable, Hashable, CaseIterable {
    case any
    case documents
    case images
    case movies
    case audio
    case archives
    case diskImages

    var includedTypes: [UTType] {
        switch self {
        case .any: []
        case .documents: [.compositeContent, .text]
        case .images: [.image]
        case .movies: [.movie]
        case .audio: [.audio]
        case .archives: [.archive]
        case .diskImages: [.diskImage]
        }
    }

    var excludedTypes: [UTType] {
        self == .documents ? [.sourceCode] : []
    }

    public func includes(_ type: UTType) -> Bool {
        guard self != .any else { return true }
        return includedTypes.contains(where: type.conforms(to:)) && !excludedTypes.contains(where: type.conforms(to:))
    }
}
