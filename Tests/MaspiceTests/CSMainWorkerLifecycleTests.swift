import CocoaSpice
import Foundation
import XCTest

private final class WeakObjectBox {
    weak var value: AnyObject?
}

final class CSMainWorkerLifecycleTests: XCTestCase {
    func testSpiceWorkerStopsAndRestartsWithIterationLoop() {
        let main = CSMain.shared
        XCTAssertTrue(main.running || main.spiceStart())

        main.spiceStop()
        XCTAssertFalse(main.running)
        XCTAssertTrue(main.spiceStart())

        let executed = expectation(description: "restarted worker executes GLib callback")
        main.async {
            executed.fulfill()
        }
        wait(for: [executed], timeout: 2)
    }

    func testSpiceWorkerDrainsAutoreleasedObjectsBetweenGLibIterations() {
        let main = CSMain.shared
        XCTAssertTrue(main.running || main.spiceStart())

        let controlObject = WeakObjectBox()
        autoreleasepool {
            controlObject.value = NSMutableArray
                .perform(NSSelectorFromString("array"))?
                .takeUnretainedValue()
            XCTAssertNotNil(controlObject.value)
        }
        XCTAssertNil(
            controlObject.value,
            "The probe object must be owned only by its autorelease pool."
        )

        let weakObject = WeakObjectBox()
        let created = expectation(description: "autoreleased object created on SPICE worker")

        main.async {
            let object = NSMutableArray
                .perform(NSSelectorFromString("array"))?
                .takeUnretainedValue()
            weakObject.value = object
            created.fulfill()
        }
        wait(for: [created], timeout: 2)

        // Cross several separately submitted GLib callbacks. A worker-level
        // autorelease pool must drain the object created by the first callback;
        // without one it remains owned until the SPICE thread exits.
        for iteration in 0..<4 where weakObject.value != nil {
            let cycled = expectation(description: "GLib cycle \(iteration) completed")
            main.async {
                cycled.fulfill()
            }
            wait(for: [cycled], timeout: 2)
        }

        XCTAssertNil(
            weakObject.value,
            "The long-lived SPICE worker is retaining autoreleased objects across GLib iterations."
        )
    }
}
