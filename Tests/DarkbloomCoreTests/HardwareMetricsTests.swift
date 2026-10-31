import Darwin
import XCTest
@testable import DarkbloomCore

final class HardwareMetricsTests: XCTestCase {
    func testSnapshotsReleaseHostPortSendRights() throws {
        // Warm up one-time sensor discovery before comparing the host port.
        _ = HardwareMetricsReader.snapshot()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var before: mach_port_urefs_t = 0
        XCTAssertEqual(mach_port_get_refs(mach_task_self_, host, MACH_PORT_RIGHT_SEND, &before), KERN_SUCCESS)

        for _ in 0..<10 {
            _ = HardwareMetricsReader.snapshot()
        }

        var after: mach_port_urefs_t = 0
        XCTAssertEqual(mach_port_get_refs(mach_task_self_, host, MACH_PORT_RIGHT_SEND, &after), KERN_SUCCESS)
        XCTAssertEqual(after, before)
    }
}
