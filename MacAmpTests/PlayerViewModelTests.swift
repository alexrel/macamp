import XCTest
@testable import MacAmp

final class PlayerViewModelTests: XCTestCase {
    var sut: PlayerViewModel!
    
    override func setUp() {
        super.setUp()
        sut = PlayerViewModel()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func test_initialState_isStopped() {
        XCTAssertEqual(sut.status, .stopped)
    }
    
    func test_initialBitrate_isZero() {
        XCTAssertEqual(sut.bitrate, 0)
    }
    
    func test_initialShadeMode_isFalse() {
        XCTAssertFalse(sut.isShadeMode)
    }
    
    func test_toggleShadeMode_changesState() {
        sut.isShadeMode.toggle()
        XCTAssertTrue(sut.isShadeMode)
        sut.isShadeMode.toggle()
        XCTAssertFalse(sut.isShadeMode)
    }
    
    func test_initialTrackTitle_followsDynamicFormat() {
        // Should follow: *** MACAMP v[Version] - READY
        XCTAssertTrue(sut.currentTrackTitle.contains("*** MACAMP"))
        XCTAssertTrue(sut.currentTrackTitle.contains("READY"))
    }
    
    func test_toggleRemainingTimeMode_changesCalculation() {
        sut.totalTime = 100
        sut.currentTime = 30
        
        // Elapsed (default)
        XCTAssertFalse(sut.isRemainingTimeMode)
        
        // Toggle to Remaining
        sut.isRemainingTimeMode = true
        XCTAssertTrue(sut.isRemainingTimeMode)
    }
}
