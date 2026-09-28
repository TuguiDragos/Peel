import PeelCore
import QuickLookThumbnailing
import SwiftUI

struct DuplicateScanProgressView: View {
    /// Read here rather than in `ContentView`, the parent view. Progress changes many times a second during a
    /// scan, and reading it there would re-run `ContentView`'s body, which builds the whole window, on every change.
    @Environment(DuplicateLibrary.self) private var duplicates

    private var progress: DuplicateScanProgress? { duplicates.progress }

    /// Shows one linear bar for the whole scan, indeterminate while no total is known. The Human Interface Guidelines
    /// advise against switching from a spinner to a progress bar.
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
            Text(headline)
                .font(.headline)
            count
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if duplicates.kind == .any {
                Text("Step \(duplicates.isOnFiles ? 2 : 1) of \(2)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 320)
        .padding()
    }

    private var fraction: Double? {
        switch progress {
        case .comparing(let compared, let total): Double(compared) / Double(max(total, 1))
        case .verifying(let read, let total): Double(read) / Double(max(total, 1))
        case .listing, .collecting, nil: nil
        }
    }

    private var headline: LocalizedStringResource {
        switch progress {
        case .listing: "Looking through folders…"
        case .collecting: "Looking for files…"
        case .comparing: duplicates.isOnFiles ? "Comparing files…" : "Comparing folders…"
        case .verifying: "Reading contents…"
        case nil: duplicates.isOnFiles ? "Looking for files…" : "Looking through folders…"
        }
    }

    @ViewBuilder
    private var count: some View {
        switch progress {
        case .listing(let found): Text("Folders found: \(found, format: .number)")
        case .collecting(let found): Text("Files found: \(found, format: .number)")
        case .comparing(let compared, let total): Text("\(compared, format: .number) of \(total, format: .number)")
        case .verifying(let read, let total): Text("\(read.byteCount) of \(total.byteCount)")
        case nil: EmptyView()
        }
    }
}

struct DuplicateSummaryView: View {
    @Environment(DuplicateLibrary.self) private var duplicates
    let scan: DuplicateScan

    var body: some View {
        VStack(spacing: 0) {
            RemovalsHeldBanner()
                .padding(.horizontal, 20)
                .padding(.top, 12)
            // Shown only when Full Disk Access would help: it can't fix a folder that is missing, or one the
            // user's account can't read.
            if scan.needsFullDiskAccess {
                FullDiskAccessBanner()
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            if !scan.notLookedIn.isEmpty {
                Notice(
                    title: Text("Peel couldn’t look in ^[\(scan.notLookedIn.count) folder](inflect: true)"),
                    detail: Text(verbatim: scan.notLookedIn.map(\.abbreviatedPath).formatted(.list(type: .and))),
                    kind: .note
                ) {}
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            ContentUnavailableView {
                Label("Duplicates Found", systemImage: "doc.on.doc")
            } description: {
                Text("^[\(duplicates.selectedCount) item](inflect: true) selected of ^[\(duplicates.copyCount) copy](inflect: true) in ^[\(duplicates.groupCount) group](inflect: true). Choose one to review its copies.")
                    .contentTransition(.numericText(value: Double(duplicates.copyCount)))
                    .motion(value: duplicates.copyCount)
            }
            // Takes the page's height, so the bar floats at its foot as on every page, not under these words.
            .frame(maxHeight: .infinity)
        }
        .safeAreaBar(edge: .bottom) {
            DuplicateRemovalBar()
        }
    }
}

struct DuplicateRemovalBar: View {
    @Environment(DuplicateLibrary.self) private var duplicates

    var body: some View {
        // The selection can include groups a search hides, so the question says how many groups it reaches.
        RemovalBar(
            page: Tool.duplicates.page(),
            isScanning: false,
            message: Text("From ^[\(groupsAffected) group](inflect: true). A selected folder goes with everything in it.")
        )
    }
}

extension DuplicateRemovalBar {
    /// The number of groups with at least one selected copy, including groups a search hides.
    var groupsAffected: Int {
        let scan = duplicates.scan
        return (scan?.groups ?? []).count { group in group.files.contains { duplicates.selectedURLs.contains($0.url) } }
            + (scan?.folderGroups ?? []).count { group in group.folders.contains { duplicates.selectedFolders.contains($0.url) } }
    }
}

struct FileThumbnail: View {
    @Environment(\.displayScale) private var displayScale
    /// The image and the file it was made for. A row can be handed another file, and must not go on showing the
    /// last one's image.
    @State private var made: (url: URL, image: NSImage)?
    let url: URL

    init(url: URL) {
        self.url = url
        _made = State(initialValue: ThumbnailCache.image(for: url).map { (url, $0) })
    }

    private var thumbnail: NSImage? {
        made?.url == url ? made?.image : nil
    }

    /// Returns a stream of the images Quick Look makes for `request`. The stream ends with the `.thumbnail` callback,
    /// which `QLThumbnailGenerator.h` promises even on failure, so an error on the low quality image doesn't end it.
    /// Nonisolated because Quick Look calls back on its own queue, where a main actor closure would crash.
    nonisolated private static func representations(of request: QLThumbnailGenerator.Request) -> AsyncStream<CGImage> {
        AsyncStream { continuation in
            QLThumbnailGenerator.shared.generateRepresentations(for: request) { representation, type, _ in
                if let image = representation?.cgImage { continuation.yield(image) }
                if type == .thumbnail { continuation.finish() }
            }
        }
    }

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .accessibilityIgnoresInvertColors()
                    .transition(.opacity)
            } else {
                AppIcon(url: url)
            }
        }
        .motion(value: thumbnail == nil)
        .task(id: url) {
            guard thumbnail == nil else { return }
            if let cached = ThumbnailCache.image(for: url) {
                made = (url, cached)
                return
            }
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 64, height: 64),
                scale: displayScale,
                // Asks for a low quality thumbnail as well, which Quick Look can return sooner, so it replaces the
                // file's generic icon while the full thumbnail is still being made.
                representationTypes: [.lowQualityThumbnail, .thumbnail]
            )
            for await image in Self.representations(of: request) {
                made = (url, NSImage(cgImage: image, size: CGSize(width: 64, height: 64)))
            }
            if let thumbnail {
                ThumbnailCache.keep(thumbnail, for: url)
            }
        }
    }
}

/// A cache of thumbnails, like `IconCache` for icons, so a row scrolled back into view doesn't ask Quick Look again.
/// It is keyed by the file as well as its path, so a file edited or replaced at that path gets a thumbnail of its own.
enum ThumbnailCache {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    @MainActor
    static func image(for url: URL) -> NSImage? {
        key(for: url).flatMap(images.object(forKey:))
    }

    @MainActor
    static func keep(_ image: NSImage, for url: URL) {
        guard let key = key(for: url) else { return }
        images.setObject(image, forKey: key)
    }

    /// The path with the item's device, inode, size and modification time. Nil for an item that is gone.
    private static func key(for url: URL) -> NSString? {
        let path = url.path(percentEncoded: false)
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return "\(path)\n\(info.st_dev) \(info.st_ino) \(info.st_size) \(info.st_mtimespec.tv_sec) \(info.st_mtimespec.tv_nsec)" as NSString
    }
}
