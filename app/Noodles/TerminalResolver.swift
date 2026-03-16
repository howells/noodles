import Foundation
import AppKit

struct TerminalResolver {
    private static let knownBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "org.alacritty",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
    ]

    static func resolve(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var current = pid

        for _ in 0..<20 {
            let ppid = getParentPid(current)
            guard ppid > 1 else { break }
            if let bundleId = NSRunningApplication(processIdentifier: ppid)?.bundleIdentifier,
               knownBundleIds.contains(bundleId) {
                return bundleId
            }
            current = ppid
        }
        return nil
    }

    private static func getParentPid(_ pid: Int32) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }
}
