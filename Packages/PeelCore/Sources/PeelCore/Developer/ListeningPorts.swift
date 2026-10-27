import Darwin

/// The TCP ports this account's processes listen on, read from each one's sockets (`PROC_PIDFDSOCKETINFO`,
/// `sys/proc_info.h`). Another account's processes, root's included, don't let Peel read them.
enum ListeningPorts {
    static func ofThisAccount() -> Set<Int> {
        var pids = [pid_t](repeating: 0, count: 8_192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var ports: Set<Int> = []
        for pid in pids.prefix(max(count, 0)) where pid > 0 && !(kill(pid, 0) != 0 && errno == EPERM) {
            ports.formUnion(listening(by: pid))
        }
        return ports
    }

    static func listening(by pid: pid_t) -> Set<Int> {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, size)
        guard filled > 0 else { return [] }
        var ports: Set<Int> = []
        for descriptor in descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.size)
        where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let expected = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, expected) == expected,
                  info.psi.soi_kind == Int32(SOCKINFO_TCP),
                  info.psi.soi_proto.pri_tcp.tcpsi_state == Int32(TSI_S_LISTEN)
            else { continue }
            // The local port is kept in network byte order.
            let port = UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
            ports.insert(Int(UInt16(bigEndian: port)))
        }
        return ports
    }
}
