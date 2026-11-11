import Foundation

// Safety: tests write session.json / playlist.json via PersistenceManager. Refuse to run against the real home.
guard let testHome = ProcessInfo.processInfo.environment["MACAMP_TEST_HOME"],
      NSHomeDirectory() == testHome else {
    print("❌ Refusing to run: start the tests via ./build.sh test (isolated CFFIXED_USER_HOME), not directly.")
    exit(2)
}

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("⚡ MacAmp Test Runner — Phase 2 Verification Suite")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

skinTests()
playlistTests()
windowTests()
audioTests()
visualizerTests()
setupTests()
interfaceTests()
pluginTests()
videoTests()
libraryTests()

print("\n🎉 ALL PHASE 2 VERIFICATION TESTS PASSED SUCCESSFULLY! 🎉\n")
