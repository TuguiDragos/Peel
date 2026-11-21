import Darwin
import Synchronization

extension ProtectedData {
    /// A look that reads each folder it looks into whole, one name at a time and keeping none, with no limit: what a
    /// move the person asked for makes of a folder too full for the look a scan makes. It counts each name it reads,
    /// stops when it is told to, and remembers what it found in each folder it looked through, so the guard asked
    /// again about one of them reads it no more.
    public final class WholeLook: Sendable {
        private let isStopped: @Sendable () -> Bool
        private let counting: @Sendable (Int) -> Void
        /// How many reads were told to stop.
        private let stops = Atomic<Int>(0)
        private let found = Mutex<[Key: any Sendable]>([:])

        public init(
            stoppingWhen isStopped: @escaping @Sendable () -> Bool = { false },
            counting: @escaping @Sendable (Int) -> Void = { _ in }
        ) {
            self.isStopped = isStopped
            self.counting = counting
        }

        /// The whole look the guard makes, when a move asked for one.
        @TaskLocal public static var current: WholeLook?

        private struct Key: Hashable {
            let look: String
            let device: dev_t
            let file: ino_t
        }

        /// What `look` found in `folder` earlier in this look, else what `finding` finds now, remembered unless a read
        /// stopped while it was found. A folder that can't be told by its numbers is looked into each time.
        package func remembered<Answer: Sendable>(
            _ look: String, in folder: String, _ finding: () -> Answer
        ) -> Answer {
            var info = stat()
            guard lstat(folder, &info) == 0 else { return finding() }
            let key = Key(look: look, device: info.st_dev, file: info.st_ino)
            if let known = found.withLock({ $0[key] }) as? Answer { return known }
            let stopsBefore = stops.load(ordering: .relaxed)
            let answer = finding()
            if stops.load(ordering: .relaxed) == stopsBefore { found.withLock { $0[key] = answer } }
            return answer
        }

        /// Calls `visit` with each name in `folder`, and whether it is a regular file, while `visit` answers true.
        /// Answers why there are none: the folder is there and could not be listed, or the look was stopped, which
        /// leaves what is inside as unknown as a folder too full to look through.
        func read(_ folder: String, followingLinks: Bool, _ visit: (String, Bool) -> Bool) -> Unlisted? {
            var info = stat()
            guard (followingLinks ? stat(folder, &info) : lstat(folder, &info)) == 0 else {
                return [ENOENT, ENOTDIR, ELOOP].contains(errno) ? nil : .closed
            }
            guard info.st_mode & S_IFMT == S_IFDIR else { return nil }
            guard let directory = opendir(folder) else { return .closed }
            defer { closedir(directory) }
            while true {
                if isStopped() {
                    stops.wrappingAdd(1, ordering: .relaxed)
                    return .tooMany
                }
                errno = 0
                guard let entry = readdir(directory) else { return errno == 0 ? nil : .closed }
                guard let (name, type) = Self.nameAndType(of: entry) else { return .closed }
                guard name != ".", name != ".." else { continue }
                counting(1)
                let isAFile: Bool
                switch type {
                case DT_REG: isAFile = true
                case DT_UNKNOWN:
                    var kind = stat()
                    isAFile = lstat(folder + "/" + name, &kind) == 0 && kind.st_mode & S_IFMT == S_IFREG
                default: isAFile = false
                }
                guard visit(name, isAFile) else { return nil }
            }
        }

        /// The name and `d_type` of `entry`, each read where it lies: `readdir` gives a record only as long as its
        /// name, so the struct's whole name field would be read past the record, and past the buffer for its last one.
        static func nameAndType(of entry: UnsafePointer<dirent>) -> (name: String, type: Int32)? {
            let record = UnsafeRawPointer(entry)
            guard let name = MemoryLayout<dirent>.offset(of: \.d_name),
                  let length = MemoryLayout<dirent>.offset(of: \.d_namlen),
                  let type = MemoryLayout<dirent>.offset(of: \.d_type)
            else { return nil }
            let bytes = UnsafeRawBufferPointer(
                start: record + name, count: Int(record.load(fromByteOffset: length, as: UInt16.self))
            )
            return (String(decoding: bytes, as: UTF8.self), Int32(record.load(fromByteOffset: type, as: UInt8.self)))
        }
    }

    /// Calls `visit` with each name in `folder` while it answers true, or answers why there are none: the folder is
    /// there and could not be listed, or holds more entries than a look reads. A whole look reads it name by name.
    package static func eachName(in folder: String, followingLinks: Bool, _ visit: (String) -> Bool) -> Unlisted? {
        if let whole = WholeLook.current {
            return whole.read(folder, followingLinks: followingLinks) { name, _ in visit(name) }
        }
        switch look(in: folder, followingLinks: followingLinks) {
        case .success(let names):
            for name in names {
                guard visit(name) else { break }
            }
            return nil
        case .failure(let unlisted):
            return unlisted
        }
    }
}
