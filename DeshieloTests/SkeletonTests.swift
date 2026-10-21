import XCTest
@testable import Deshielo

final class SkeletonTests: XCTestCase {
    func testSharedCodeIsCompiledIntoApp() {
        XCTAssertEqual(SharedInfo.appName, "Deshielo")
    }
}
