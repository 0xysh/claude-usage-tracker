import XCTest
@testable import Claude_Usage

final class UsageMotionTests: XCTestCase {
    func testCorruptAndNegativePercentagesNeverProduceAnInvalidFill() {
        for percentage in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: percentage, progress: 0.5,
                                                          reduceMotion: false), 0)
        }
    }

    func testFillTracksItsPercentageAndClampsOverQuotaReadings() {
        XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: 72, progress: 0.5,
                                                      reduceMotion: false), 0.36, accuracy: 0.0001)
        for percentage in [100.0, 150, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: percentage, progress: 0.5,
                                                          reduceMotion: false), 0.5)
        }
    }

    func testEntranceEndpointsDoNotOvershootOrInvertTheBar() {
        XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: 80, progress: -1,
                                                      reduceMotion: false), 0)
        XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: 80, progress: 0,
                                                      reduceMotion: false), 0)
        XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: 80, progress: 1,
                                                      reduceMotion: false), 0.8)
        XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: 80, progress: 2,
                                                      reduceMotion: false), 0.8)
    }

    func testReduceMotionAlwaysUsesTheMeasuredEndpoint() {
        for progress in [CGFloat(-1), 0, 0.3, 1, 2, .nan, .infinity] {
            XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: 80, progress: progress,
                                                          reduceMotion: true), 0.8)
        }
        XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: 0, progress: 0,
                                                      reduceMotion: true), 0)
    }

    func testInvalidAnimationProgressSettlesWithoutInvalidGeometry() {
        for progress in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertEqual(UsageMotionGeometry.fillFraction(percentage: 40, progress: progress,
                                                          reduceMotion: false), 0.4)
        }
    }

    func testMarkerStaysInsideTrackAtBothEdgesAndAtItsMeasuredCenter() {
        XCTAssertEqual(UsageMotionGeometry.markerOrigin(fraction: -1, trackWidth: 100), 0)
        XCTAssertEqual(UsageMotionGeometry.markerOrigin(fraction: 0, trackWidth: 100), 0)
        XCTAssertEqual(UsageMotionGeometry.markerOrigin(fraction: 0.5, trackWidth: 100), 48.75)
        XCTAssertEqual(UsageMotionGeometry.markerOrigin(fraction: 1, trackWidth: 100), 97.5)
        XCTAssertEqual(UsageMotionGeometry.markerOrigin(fraction: 2, trackWidth: 100), 97.5)
        XCTAssertEqual(UsageMotionGeometry.markerOrigin(fraction: 1, trackWidth: 1), 0)
    }

    func testMissingOrCorruptMarkersAndTracksAreNotPlaced() {
        for fraction in [CGFloat?.none, .some(.nan), .some(.infinity), .some(-.infinity)] {
            XCTAssertNil(UsageMotionGeometry.markerOrigin(fraction: fraction, trackWidth: 100))
        }
        for width in [CGFloat(-1), 0, .nan, .infinity] {
            XCTAssertNil(UsageMotionGeometry.markerOrigin(fraction: 0.5, trackWidth: width))
            XCTAssertEqual(UsageMotionGeometry.trackWidth(width), 0)
        }
        XCTAssertNil(UsageMotionGeometry.markerOrigin(fraction: 0.5, trackWidth: 100, markerWidth: 0))
    }

    func testMissingPercentageIsDistinctFromMeasuredZero() {
        XCTAssertNil(UsageMotionGeometry.numericValue(nil))
        XCTAssertEqual(MenuBarUsagePresentation.percentageText(nil), "—")
        XCTAssertEqual(UsageMotionGeometry.numericValue(0), 0)
        XCTAssertEqual(MenuBarUsagePresentation.percentageText(0), "0%")
        for percentage in [Double.nan, .infinity, -1] {
            XCTAssertNil(UsageMotionGeometry.numericValue(percentage))
            XCTAssertEqual(MenuBarUsagePresentation.percentageText(percentage), "—")
        }
    }

    func testFractionalRefreshesKeepTheSameVisibleMotionTarget() {
        XCTAssertEqual(UsageMotionGeometry.numericValue(8.01), UsageMotionGeometry.numericValue(8.99))
        XCTAssertEqual(MenuBarUsagePresentation.percentageText(8.01),
                       MenuBarUsagePresentation.percentageText(8.99))
        XCTAssertNotEqual(UsageMotionGeometry.numericValue(8.99), UsageMotionGeometry.numericValue(9))
    }

    func testNumericEntranceCoordinatesWithTheBarAndKeepsTheActualEndpoint() {
        XCTAssertEqual(UsageMotionGeometry.presentedPercentage(80.9, progress: 0, reduceMotion: false), 0)
        XCTAssertEqual(UsageMotionGeometry.presentedPercentage(80.9, progress: 0.5, reduceMotion: false), 40)
        XCTAssertEqual(UsageMotionGeometry.presentedPercentage(80.9, progress: 1, reduceMotion: false), 80.9)
        for progress in [CGFloat(0), 0.5, 1] {
            XCTAssertEqual(UsageMotionGeometry.presentedPercentage(0, progress: progress, reduceMotion: false), 0)
            XCTAssertNil(UsageMotionGeometry.presentedPercentage(nil, progress: progress, reduceMotion: false))
        }
    }

    func testReducedNumericMotionSkipsTransientFiguresAndPreservesOverflowSuffix() {
        XCTAssertEqual(UsageMotionGeometry.presentedPercentage(80.9, progress: 0, reduceMotion: true), 80.9)
        let overflow = UsageMotionGeometry.presentedPercentage(1_000, progress: 0, reduceMotion: true)
        XCTAssertEqual(MenuBarUsagePresentation.percentageText(overflow), "999%+")
        XCTAssertNil(UsageMotionGeometry.presentedPercentage(.nan, progress: 0, reduceMotion: true))
    }

    func testOversizedFiguresKeepExistingOverflowFormattingWithoutUnboundedAnimationValues() {
        XCTAssertEqual(MenuBarUsagePresentation.percentageText(999), "999%")
        for percentage in [999.01, 1_000, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(MenuBarUsagePresentation.percentageText(percentage), "999%+")
            XCTAssertEqual(UsageMotionGeometry.numericValue(percentage), 999)
        }
    }
}
