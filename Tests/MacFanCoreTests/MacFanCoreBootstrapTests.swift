import XCTest
@testable import MacFanCore

final class MacFanCoreBootstrapTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertNotNil(MacFanCoreBootstrap.self)
    }
}
