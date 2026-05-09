import XCTest
@testable import MacParakeetCore

@MainActor
final class ClipboardServiceTests: XCTestCase {
    func testDefaultRestoreDelayLeavesRoomForAsyncPasteConsumers() {
        XCTAssertGreaterThanOrEqual(
            ClipboardService.defaultClipboardRestoreDelay,
            0.75,
            "Restoring too soon can make slow target apps paste the previously saved clipboard item."
        )
    }

    func testPasteboardWriteFailureHasActionableDescription() {
        XCTAssertEqual(
            ClipboardServiceError.pasteboardWriteFailed.errorDescription,
            "Paste automation unavailable (could not write transcript to the clipboard)."
        )
    }
}
