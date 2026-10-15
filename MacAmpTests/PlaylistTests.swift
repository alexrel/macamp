import XCTest
@testable import MacAmp

final class PlaylistTests: XCTestCase {
    var sut: Playlist!
    
    override func setUp() {
        super.setUp()
        sut = Playlist()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func test_emptyPlaylist_currenTrackIsNil() {
        XCTAssertNil(sut.currentTrack)
    }
    
    func test_addTrack_setsCurrentTrackToFirst() {
        let track = mockTrack(id: 1)
        sut.add(track: track)
        XCTAssertEqual(sut.currentTrack?.title, track.title)
    }
    
    func test_next_linearGoesForward() {
        let t1 = mockTrack(id: 1)
        let t2 = mockTrack(id: 2)
        sut.add(tracks: [t1, t2])
        
        let next = sut.next()
        XCTAssertEqual(next?.title, t2.title)
        XCTAssertEqual(sut.currentIndex, 1)
    }
    
    func test_next_atEnd_withRepeatLoops() {
        sut.isRepeat = true
        let t1 = mockTrack(id: 1)
        sut.add(track: t1)
        
        // Go past end
        let next = sut.next()
        XCTAssertEqual(next?.title, t1.title)
        XCTAssertEqual(sut.currentIndex, 0)
    }
    
    func test_next_atEnd_withoutRepeatReturnsNil() {
        sut.isRepeat = false
        let t1 = mockTrack(id: 1)
        sut.add(track: t1)
        
        let next = sut.next()
        XCTAssertNil(next)
    }
    
    func test_prev_linearGoesBack() {
        let t1 = mockTrack(id: 1)
        let t2 = mockTrack(id: 2)
        sut.add(tracks: [t1, t2])
        sut.setIndex(1)
        
        let prev = sut.previous()
        XCTAssertEqual(prev?.title, t1.title)
        XCTAssertEqual(sut.currentIndex, 0)
    }
    
    private func mockTrack(id: Int) -> Track {
        return Track(
            url: URL(fileURLWithPath: "test\(id).mp3"),
            title: "Track \(id)",
            artist: "Artist \(id)",
            duration: 100,
            bitrate: 128,
            sampleRate: 44,
            audioMode: .stereo
        )
    }
}
