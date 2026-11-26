import XCTest

final class FlowUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    private func launch(language: String = "en", reset: Bool = true, extra: [String] = []) {
        let regions = ["ja": "ja_JP", "en": "en_US", "zh-Hans": "zh_CN", "zh-Hant": "zh_TW"]
        app.launchArguments = ["-ui-testing", "-seed", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", regions[language] ?? "en_US"]
            + (reset ? ["-reset"] : []) + extra
        app.launchEnvironment["SHOTPDF_TEST_PASTE"] =
            "A4P1:eyJkYXRlIjp0cnVlLCJncmlkIjoyLCJtYXJnaW4iOjEwLCJudW1iZXJzIjp0cnVlLCJzcGxpdExvbmciOnRydWV9"
        app.launch()
    }

    private func tap(_ id: String, fallback: String? = nil, scroll: Bool = false,
                     file: StaticString = #filePath, line: UInt = #line) {
        let primary = app.buttons[id].firstMatch
        let button = fallback != nil && !primary.exists ? app.buttons[fallback ?? ""].firstMatch : primary
        XCTAssertTrue(button.waitForExistence(timeout: 12), id, file: file, line: line)
        if scroll {
            let area = app.scrollViews.firstMatch
            for turn in 0..<7 where !button.isHittable {
                if turn < 5 { area.swipeUp() } else { area.swipeDown() }
            }
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            button.exists && button.isEnabled && button.isHittable
        }, object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed, id, file: file, line: line)
        button.tap()
    }

    private func pickAll(from button: String = "home.pick") {
        tap(button)
        tap("examples.all")
        tap("examples.add")
        XCTAssertTrue(app.staticTexts["batch.count"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["batch.count"].label, "24")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),
                                              object: app.buttons["batch.layout"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed)
    }

    private func shot(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        item.name = name
        item.lifetime = .keepAlways
        add(item)
    }

    func testSeededFlowSortingLayoutPreviewExportAndShareCard() {
        launch()
        pickAll()
        tap("batch.sort")
        tap("sort.descending", fallback: "Capture date ↓")
        XCTAssertEqual(app.staticTexts["shot.title.0"].label, "Image 23")
        tap("shot.menu.0")
        tap("shot.down.0", fallback: "Move down")
        XCTAssertEqual(app.staticTexts["shot.title.0"].label, "Image 22")
        tap("batch.layout")
        tap("layout.grid.4")
        tap("batch.preview")
        XCTAssertTrue(app.staticTexts["preview.size"].waitForExistence(timeout: 45))
        tap("preview.split", scroll: true)
        XCTAssertTrue(app.descendants(matching: .any)["split.handle"].firstMatch.waitForExistence(timeout: 15))
        let handle = app.descendants(matching: .any)["split.handle"].firstMatch
        let center = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -38)))
        XCTAssertTrue(app.buttons["split.undo"].waitForExistence(timeout: 8))
        tap("split.undo")
        tap("split.apply")
        XCTAssertTrue(app.staticTexts["preview.size"].waitForExistence(timeout: 45))
        tap("preview.export")
        XCTAssertTrue(app.staticTexts["finished.file"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts["finished.card"].exists)
        tap("finished.card.share", scroll: true)
        let shareControls = app.buttons.matching(NSPredicate(format: "label IN %@", ["Copy", "AirDrop", "Close"]))
        XCTAssertTrue(shareControls.firstMatch.waitForExistence(timeout: 20))
    }

    func testDirectExportNextBatchCancelAndDraftRecovery() {
        launch()
        pickAll()
        tap("batch.export")
        XCTAssertTrue(app.staticTexts["finished.file"].waitForExistence(timeout: 45))
        tap("finished.next")
        tap("examples.close")
        XCTAssertTrue(app.staticTexts["finished.file"].exists)
        tap("finished.next")
        tap("examples.item.1")
        tap("examples.add")
        XCTAssertTrue(app.staticTexts["batch.count"].waitForExistence(timeout: 25))
        XCTAssertEqual(app.staticTexts["batch.count"].label, "1")
        app.terminate()
        launch(reset: false)
        tap("home.resume", scroll: true)
        XCTAssertEqual(app.staticTexts["batch.count"].label, "1")
    }

    func testExpiredPlanExportsOnlyAfterChoosingFirstTen() {
        launch(extra: ["-expired"])
        pickAll()
        XCTAssertFalse(app.buttons["batch.export"].exists)
        tap("batch.firstTen")
        XCTAssertTrue(app.staticTexts["finished.file"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["finished.size"].label.contains("5 pages"))
        tap("finished.edit")
        XCTAssertEqual(app.staticTexts["batch.count"].label, "24")
    }

    func testPresetPreviewAndApply() {
        launch()
        tap("home.preset")
        tap("preset.paste")
        XCTAssertTrue(app.buttons["preset.apply"].isEnabled)
        tap("preset.apply")
        tap("home.layout")
        let number = app.switches["layout.numbers"].firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 10))
        XCTAssertEqual(number.value as? String, "1")
    }

    private func store(_ language: String) {
        launch(language: language)
        XCTAssertTrue(app.buttons["home.pick"].waitForExistence(timeout: 16))
        shot("store-\(language)-01-home")
        pickAll()
        shot("store-\(language)-02-arrange")
        tap("batch.layout")
        for id in ["layout.numbers", "layout.date"] {
            let control = app.switches[id].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 10))
            if control.value as? String == "0" {
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
                let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: control)
                XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 8), .completed)
            }
        }
        shot("store-\(language)-03-layout")
        tap("layout.grid.2")
        tap("batch.preview")
        XCTAssertTrue(app.staticTexts["preview.size"].waitForExistence(timeout: 45))
        tap("preview.split", scroll: true)
        XCTAssertTrue(app.descendants(matching: .any)["split.handle"].firstMatch.waitForExistence(timeout: 15))
        shot("store-\(language)-04-split")
        tap("split.back")
        tap("preview.export")
        XCTAssertTrue(app.staticTexts["finished.card"].waitForExistence(timeout: 20))
        shot("store-\(language)-05-result")
    }

    func testStoreJapanese() { store("ja") }
    func testStoreEnglish() { store("en") }
    func testStoreSimplified() { store("zh-Hans") }
    func testStoreTraditional() { store("zh-Hant") }

    func testPaidScreenshot() {
        launch(language: "zh-Hans", extra: ["-paywall", "-expired"])
        XCTAssertTrue(app.staticTexts["purchase.expired"].waitForExistence(timeout: 14))
        shot("paid-01-paywall")
    }
}
