import Darwin

/// The files a process of this account maps shared and writable. A write through such a mapping reaches the file
/// without moving its modification or status change time until the mapping is synced (`msync(2)`), so what was
/// learned of the file before can't be believed meanwhile. Root's and other accounts' processes can't be read.
enum MappedForWriting {
    static func files() -> Set<FileIdentity.Link> {
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let size = Int32(MemoryLayout<proc_regionwithpathinfo>.size)
        var files: Set<FileIdentity.Link> = []
        for pid in pids.prefix(max(0, Int(count))) where pid > 0 {
            var address: UInt64 = 0
            var info = proc_regionwithpathinfo()
            while proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, size) == size {
                let region = info.prp_prinfo
                let hasAFile = withUnsafeBytes(of: info.prp_vip.vip_path) { $0.first ?? 0 } != 0
                // `mmap(2)` shares what `MAP_SHARED` maps with a child (`VM_INHERIT_SHARE`) and copies the rest, while
                // the region's share mode says private for a file mapped either way.
                if hasAFile, Int32(region.pri_protection) & VM_PROT_WRITE != 0,
                   region.pri_inheritance == UInt32(VM_INHERIT_SHARE) {
                    let file = info.prp_vip.vip_vi.vi_stat
                    files.insert(FileIdentity.Link(device: dev_t(file.vst_dev), inode: ino_t(file.vst_ino)))
                }
                let next = region.pri_address + region.pri_size
                guard next > address else { break }
                address = next
            }
        }
        return files
    }
}
