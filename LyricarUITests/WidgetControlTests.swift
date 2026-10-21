import XCTest

/// Reproduces "widget song controls do nothing": the app is not running, a widget
/// button is tapped on the Home Screen. The app logs (checked by the runner script)
/// must show the intent arriving and the command being sent.
final class WidgetControlTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testRemoteWidgetNextWhileAppIsNotRunning() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LyricarDemo", "-LyricarStickyDemo"]
        app.launch()
        sleep(6)
        XCUIDevice.shared.press(.home)
        sleep(2)
        addWidget(titled: "Remote")
        let done = springboard.buttons["Fertig"].firstMatch
        if done.waitForExistence(timeout: 5) { done.tap() }
        sleep(3)

        app.terminate()
        sleep(2)
        XCTAssertEqual(app.state, .notRunning)

        let next = springboard.buttons["Next song"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 10), springboard.debugDescription)
        print("WIDGET-TAP next at \(Date())")
        next.tap()
        sleep(8)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "remote-widget-after-next"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Widgets already on the Home Screen: terminate the app, tap Next.
    func testTapNextWithAppTerminated() throws {
        let app = XCUIApplication()
        app.terminate()
        XCUIDevice.shared.press(.home)
        sleep(2)
        // Find the Remote widget: its Next button is the tall one (34 pt); Verse Large
        // has a small one. Swipe through Home Screen pages until a tall one shows.
        let nexts = springboard.buttons.matching(identifier: "Next song")
        var remoteNext: XCUIElement?
        for _ in 0..<5 {
            remoteNext = (0..<nexts.count).map { nexts.element(boundBy: $0) }
                .first { $0.isHittable && $0.frame.height >= 30 }
            if remoteNext != nil { break }
            springboard.swipeLeft()
            sleep(1)
        }
        let next = try XCTUnwrap(remoteNext, "Remote widget not on any Home Screen page")
        print("WIDGET-TAP remote next frame=\(next.frame)")
        next.tap()
        sleep(8)
    }

    private func addWidget(titled title: String) {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 2)
        let edit = springboard.buttons["Bearbeiten"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let addButton = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Widget'")).firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Lyricar")
        let cell = springboard.cells["Lyricar"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        sleep(2)
        // Swipe through the gallery pages until the wanted widget's title shows.
        for _ in 0..<9 where !springboard.staticTexts[title].exists {
            springboard.swipeLeft()
            sleep(1)
        }
        XCTAssertTrue(springboard.staticTexts[title].exists, "widget \(title) not found in gallery")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "widget-picker-page"
        shot.lifetime = .keepAlways
        add(shot)
        let confirm = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'hinzufügen'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        sleep(2)
    }
}
