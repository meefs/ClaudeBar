import XCTest
@testable import Infrastructure
@testable import Domain

final class KiroUsageProbeParsingTests: XCTestCase {
    
    func testParseNormalOutput() throws {
        let output = """
        Estimated Usage | resets on 03/01 | KIRO FREE
        
        🎁 Bonus credits: 122.54/500 credits used, expires in 29 days
        
        Credits (0.00 of 50 covered in plan)
        ████████████████████████████████████████████████████████████████████████████████ 0%
        """
        
        let snapshot = try KiroUsageProbe.parse(output)
        
        XCTAssertEqual(snapshot.providerId, "kiro")
        XCTAssertEqual(snapshot.quotas.count, 2)
        
        // Bonus credits (weekly)
        let bonus = snapshot.quotas.first { $0.quotaType == .weekly }
        XCTAssertNotNil(bonus)
        if let bonus = bonus {
            XCTAssertEqual(bonus.percentRemaining, 75.492, accuracy: 0.01)
            XCTAssertNotNil(bonus.resetsAt)
            XCTAssertEqual(bonus.resetText, "Expires in 29 days")
        }
        
        // Regular credits (monthly)
        let regular = snapshot.quotas.first { $0.quotaType == .timeLimit("Monthly") }
        XCTAssertNotNil(regular)
        if let regular = regular {
            XCTAssertEqual(regular.percentRemaining, 100.0, accuracy: 0.01)
            XCTAssertNotNil(regular.resetsAt)
            XCTAssertEqual(regular.resetText, "Resets on 03/01")
        }
    }
    
    func testParseBonusCreditsOnly() throws {
        let output = """
        🎁 Bonus credits: 250.0/500 credits used, expires in 15 days
        """
        
        let snapshot = try KiroUsageProbe.parse(output)
        
        XCTAssertEqual(snapshot.quotas.count, 1)
        XCTAssertEqual(snapshot.quotas[0].quotaType, .weekly)
        XCTAssertEqual(snapshot.quotas[0].percentRemaining, 50.0, accuracy: 0.01)
    }
    
    func testParseRegularCreditsOnly() throws {
        let output = """
        Credits (25.0 of 50 covered in plan)
        resets on 03/15
        """
        
        let snapshot = try KiroUsageProbe.parse(output)
        
        XCTAssertEqual(snapshot.quotas.count, 1)
        XCTAssertEqual(snapshot.quotas[0].quotaType, .timeLimit("Monthly"))
        XCTAssertEqual(snapshot.quotas[0].percentRemaining, 50.0, accuracy: 0.01)
    }
    
    func testParseEmptyOutput() {
        let output = ""
        
        XCTAssertThrowsError(try KiroUsageProbe.parse(output)) { error in
            guard case ProbeError.parseFailed = error else {
                XCTFail("Expected parseFailed error")
                return
            }
        }
    }
    
    func testParseMalformedOutput() {
        let output = "Some random text without quota data"
        
        XCTAssertThrowsError(try KiroUsageProbe.parse(output)) { error in
            guard case ProbeError.parseFailed = error else {
                XCTFail("Expected parseFailed error")
                return
            }
        }
    }
    
    func testParseZeroTotalCredits() throws {
        let output = """
        🎁 Bonus credits: 0.0/0 credits used, expires in 10 days
        Credits (0.00 of 0 covered in plan)
        """
        
        // Should not crash with division by zero
        // Should skip quotas with zero total
        XCTAssertThrowsError(try KiroUsageProbe.parse(output)) { error in
            guard case ProbeError.parseFailed = error else {
                XCTFail("Expected parseFailed error when no valid quotas")
                return
            }
        }
    }
    
    func testParseWithoutResetInfo() throws {
        let output = """
        🎁 Bonus credits: 100.0/500 credits used
        Credits (10.0 of 50 covered in plan)
        """
        
        let snapshot = try KiroUsageProbe.parse(output)
        
        XCTAssertEqual(snapshot.quotas.count, 2)
        
        // Both should have nil resetsAt and resetText
        for quota in snapshot.quotas {
            XCTAssertNil(quota.resetsAt)
            XCTAssertNil(quota.resetText)
        }
    }
    
    func testParseWithANSIEscapeCodes() throws {
        let output = """
        \u{001B}[38;5;141mEstimated Usage\u{001B}[0m | resets on 03/01 | \u{001B}[38;5;141mKIRO FREE\u{001B}[0m
        
        \u{001B}[1m🎁 Bonus credits:\u{001B}[0m \u{001B}[1m122.54/500\u{001B}[0m credits used, expires in \u{001B}[1m29\u{001B}[0m days
        
        \u{001B}[1mCredits\u{001B}[0m (0.00 of 50 covered in plan)
        """
        
        let snapshot = try KiroUsageProbe.parse(output)
        
        XCTAssertEqual(snapshot.quotas.count, 2)
        XCTAssertEqual(snapshot.quotas[0].percentRemaining, 75.492, accuracy: 0.01)
        XCTAssertEqual(snapshot.quotas[1].percentRemaining, 100.0, accuracy: 0.01)
    }
}
