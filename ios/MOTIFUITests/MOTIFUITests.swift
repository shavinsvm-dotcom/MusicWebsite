import XCTest

final class MOTIFUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--motif-ui-testing"]
        app.launch()
    }

    func testSongInfoLyricsTimingAndStorage() throws {
        let libraryTab = app.tabBars.buttons["Library"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 30), "App never reached the tab bar")
        libraryTab.tap()

        let playRow = app.buttons["Play UI Test Track"].firstMatch
        XCTAssertTrue(playRow.waitForExistence(timeout: 15), "Seeded track is missing from the library")
        capture("library")

        // Song Info from the row menu.
        let more = element("track.more")
        XCTAssertTrue(more.waitForExistence(timeout: 10), "Track menu button is missing")
        more.tap()

        let songInfo = app.buttons["Song Info"]
        XCTAssertTrue(songInfo.waitForExistence(timeout: 5), "Song Info menu item is missing")
        songInfo.tap()

        XCTAssertTrue(
            app.navigationBars["Song Info"].waitForExistence(timeout: 10),
            "Song Info did not open"
        )
        XCTAssertTrue(
            app.staticTexts["UI Test Track"].waitForExistence(timeout: 5),
            "Song Info does not show the track title"
        )
        capture("song-info")
        app.buttons["Done"].tap()

        // Play the track, open the full player, then open lyrics.
        playRow.tap()
        let miniPlayer = element("mini.player")
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 15), "Mini player did not appear")
        miniPlayer.tap()
        XCTAssertTrue(
            app.buttons["Close player"].waitForExistence(timeout: 10),
            "Player did not open"
        )

        let lyricsMenu = element("player.lyrics")
        XCTAssertTrue(lyricsMenu.waitForExistence(timeout: 10), "Lyrics control is missing")
        lyricsMenu.tap()

        let viewLyrics = app.buttons["View Lyrics"]
        XCTAssertTrue(viewLyrics.waitForExistence(timeout: 5), "View Lyrics item is missing")
        viewLyrics.tap()

        // Exercise the timing nudge and prove it stuck by reopening the menu.
        let timing = element("lyrics.timing")
        XCTAssertTrue(timing.waitForExistence(timeout: 10), "Lyrics timing control is missing")
        timing.tap()

        let later = app.buttons["0.5s Later"]
        XCTAssertTrue(later.waitForExistence(timeout: 5), "Lyrics timing menu did not open")
        later.tap()

        Thread.sleep(forTimeInterval: 0.6)
        timing.tap()
        XCTAssertTrue(
            app.buttons["Reset Timing"].waitForExistence(timeout: 5),
            "Lyrics timing change did not persist"
        )
        capture("lyrics-timing")
        app.buttons["Reset Timing"].tap()

        app.buttons["Done"].tap()
        XCTAssertTrue(
            app.buttons["Close player"].waitForExistence(timeout: 5),
            "Lyrics did not close"
        )
        app.buttons["Close player"].tap()

        // Storage management lives in Settings.
        let settings = element("library.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings button is missing")
        settings.tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 10),
            "Settings did not open"
        )

        let imported = app.staticTexts["Imported Music"]
        for _ in 0..<6 {
            if imported.exists && imported.isHittable { break }
            app.swipeUp()
        }

        XCTAssertTrue(imported.waitForExistence(timeout: 5), "Storage section is missing")
        XCTAssertTrue(app.staticTexts["Downloads"].exists, "Downloads row is missing")
        XCTAssertTrue(
            app.buttons["Remove All Downloads"].exists,
            "Remove All Downloads action is missing"
        )
        capture("storage")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
