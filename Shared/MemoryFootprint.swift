import Foundation

/// Memory numbers that matter for the keyboard extension's kill limit.
enum MemoryFootprint {
    /// `phys_footprint`: the figure iOS compares against the process memory limit.
    static func currentBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    /// How much more this process may allocate before iOS kills it.
    static func availableBytes() -> Int {
        os_proc_available_memory()
    }

    static func summary() -> String {
        let used = currentBytes().map { Self.mb($0) } ?? "?"
        let free = Self.mb(UInt64(max(0, availableBytes())))
        return "memory: \(used) MB used, \(free) MB headroom"
    }

    private static func mb(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}
