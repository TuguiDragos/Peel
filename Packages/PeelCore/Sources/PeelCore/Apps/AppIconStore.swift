public import AppKit
public import Foundation
internal import PeelPrivileged
import Synchronization

/// Apps' icons, let go only by Peel. Under memory pressure an `NSCache` gives back what it was just given, and rows
/// would make their icons again without end.
public final class AppIconStore: Sendable {
    public static let othersLimit = 256

    /// An image made on one thread can be drawn on another.
    private final class Icon: @unchecked Sendable {
        let image: NSImage

        init(_ image: NSImage) {
            self.image = image
        }
    }

    private struct State {
        var held: [String: Icon] = [:]
        var kept: [String: URL] = [:]
        /// Held but kept by no list, oldest first.
        var others: [String] = []
        /// Only the latest making of a place counts.
        var making: [String: Int] = [:]
        var waiting: Set<String> = []
        var started = 0

        mutating func start(_ place: String) -> Int {
            started += 1
            making[place] = started
            return started
        }

        mutating func letOthersGo() {
            while others.count > AppIconStore.othersLimit {
                let oldest = others.removeFirst()
                if kept[oldest] == nil { held[oldest] = nil }
            }
        }
    }

    private let state = Mutex(State())
    private let make: @Sendable (URL) async -> NSImage
    private let arrived: @MainActor @Sendable () -> Void

    public init(make: @escaping @Sendable (URL) async -> NSImage, arrived: @escaping @MainActor @Sendable () -> Void) {
        self.make = make
        self.arrived = arrived
    }

    /// Nil while the icon is made; the row is told once it is.
    @MainActor
    public func icon(for url: URL) -> NSImage? {
        let place = Self.place(of: url)
        let (icon, number): (Icon?, Int?) = state.withLock { state in
            if let icon = state.held[place] { return (icon, nil) }
            state.waiting.insert(place)
            return (nil, state.making[place] == nil ? state.start(place) : nil)
        }
        if let number {
            Task { await made(url, at: place, number: number) }
        }
        return icon?.image
    }

    /// Makes the icons a list shows and keeps them until they are forgotten.
    @concurrent
    public func keep(_ urls: [URL]) async {
        for url in urls {
            let place = Self.place(of: url)
            let number: Int? = state.withLock { state in
                if state.kept.updateValue(url, forKey: place) == nil, state.held[place] != nil {
                    state.others.removeAll { $0 == place }
                }
                return state.held[place] == nil && state.making[place] == nil ? state.start(place) : nil
            }
            if let number { await made(url, at: place, number: number) }
        }
    }

    /// Also lets go of the apps inside these.
    @MainActor
    public func forget(_ urls: some Sequence<URL>) {
        let places = Set(urls.map(Self.place(of:)))
        guard !places.isEmpty else { return }
        let wasWaited = state.withLock { state in
            let isForgotten = { (place: String) in Self.isAtOrInside(place, anyOf: places) }
            state.held = state.held.filter { !isForgotten($0.key) }
            state.kept = state.kept.filter { !isForgotten($0.key) }
            state.others.removeAll(where: isForgotten)
            state.making = state.making.filter { !isForgotten($0.key) }
            let waited = state.waiting.filter(isForgotten)
            state.waiting.subtract(waited)
            return !waited.isEmpty
        }
        // Else a waiting row would wait for good.
        if wasWaited { arrived() }
    }

    /// Makes what lists keep once more.
    @MainActor @discardableResult
    public func forgetAll() -> Task<Void, Never> {
        let (kept, wasWaited) = state.withLock { state in
            let wasWaited = !state.waiting.isEmpty
            state.held = [:]
            state.others = []
            state.making = [:]
            state.waiting = []
            return (Array(state.kept.values), wasWaited)
        }
        if wasWaited { arrived() }
        return Task { await keep(kept) }
    }

    @concurrent
    private func made(_ url: URL, at place: String, number: Int) async {
        let icon = Icon(await make(url))
        let isWaited = state.withLock { state in
            guard state.making[place] == number else { return false }
            state.making[place] = nil
            state.held[place] = icon
            if state.kept[place] == nil {
                state.others.append(place)
                state.letOthersGo()
            }
            return state.waiting.remove(place) != nil
        }
        if isWaited { await arrived() }
    }

    /// One key whether or not the URL ends in a slash.
    private static func place(of url: URL) -> String {
        "/" + PathComponents.of(url.path(percentEncoded: false)).joined(separator: "/")
    }

    private static func isAtOrInside(_ place: String, anyOf places: Set<String>) -> Bool {
        var folder = ""
        for name in PathComponents.of(place) {
            folder += "/" + name
            if places.contains(folder) { return true }
        }
        return false
    }
}
