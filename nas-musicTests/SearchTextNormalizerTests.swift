//
//  SearchTextNormalizerTests.swift
//  nas-musicTests
//

import XCTest
@testable import nas_music

final class SearchTextNormalizerTests: XCTestCase {
    func testNormalizeTrimsLowercasesFoldsAndCollapsesSpaces() {
        XCTAssertEqual(SearchTextNormalizer.normalize("  Café   DEL  Mar  "), "cafe del mar")
        XCTAssertEqual(SearchTextNormalizer.normalize("  周杰伦   夜曲 "), "周杰伦 夜曲")
    }

    func testEscapedLikePatternEscapesWildcards() {
        XCTAssertEqual(SearchTextNormalizer.escapedLikePattern(for: "100%_ok\\"), "%100\\%\\_ok\\\\%")
    }
}
