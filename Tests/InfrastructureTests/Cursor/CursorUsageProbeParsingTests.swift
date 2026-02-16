import Foundation
import Testing
@testable import Infrastructure
@testable import Domain

@Suite("CursorUsageProbe Parsing Tests")
struct CursorUsageProbeParsingTests {

    // MARK: - Real API Response

    @Test
    func `parse real ultra plan response`() throws {
        // Actual response from cursor.com/api/usage-summary
        let json = """
        {
            "billingCycleStart": "2026-02-06T03:34:49.000Z",
            "billingCycleEnd": "2026-03-06T03:34:49.000Z",
            "membershipType": "ultra",
            "limitType": "user",
            "isUnlimited": false,
            "autoModelSelectedDisplayMessage": "You've used 1% of your included total usage",
            "namedModelSelectedDisplayMessage": "You've used 1% of your included API usage",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 326,
                    "limit": 40000,
                    "remaining": 39674,
                    "breakdown": { "included": 326, "bonus": 0, "total": 326 },
                    "autoPercentUsed": 0.033,
                    "apiPercentUsed": 0.586,
                    "totalPercentUsed": 0.217
                },
                "onDemand": {
                    "enabled": false,
                    "used": 0,
                    "limit": null,
                    "remaining": null
                }
            },
            "teamUsage": {}
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.providerId == "cursor")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.accountTier == .custom("ULTRA"))

        let quota = snapshot.quotas[0]
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(abs(quota.percentRemaining - 99.185) < 0.01)
        #expect(quota.resetText == "326/40000 requests")
        #expect(quota.resetsAt != nil)
    }

    // MARK: - Plan Usage

    @Test
    func `parse pro plan with plan usage`() throws {
        let json = """
        {
            "membershipType": "pro",
            "billingCycleEnd": "2025-02-01T00:00:00Z",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 123,
                    "limit": 500,
                    "remaining": 377
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.providerId == "cursor")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.accountTier == .custom("PRO"))

        let quota = snapshot.quotas[0]
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(abs(quota.percentRemaining - 75.4) < 0.1)
        #expect(quota.resetText == "123/500 requests")
        #expect(quota.resetsAt != nil)
    }

    @Test
    func `parse plan with on-demand usage enabled`() throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 400,
                    "limit": 500,
                    "remaining": 100
                },
                "onDemand": {
                    "enabled": true,
                    "used": 25,
                    "limit": 100,
                    "remaining": 75
                }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas.count == 2)

        let plan = snapshot.quotas.first { $0.quotaType == .timeLimit("Monthly") }
        #expect(plan != nil)
        #expect(abs(plan!.percentRemaining - 20.0) < 0.1)
        #expect(plan!.resetText == "400/500 requests")

        let onDemand = snapshot.quotas.first { $0.quotaType == .timeLimit("On-Demand") }
        #expect(onDemand != nil)
        #expect(abs(onDemand!.percentRemaining - 75.0) < 0.1)
    }

    @Test
    func `parse depleted plan usage`() throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 500,
                    "limit": 500,
                    "remaining": 0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].percentRemaining == 0)
        #expect(snapshot.quotas[0].resetText == "500/500 requests")
    }

    @Test
    func `parse over-limit usage clamps to zero`() throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 550,
                    "limit": 500,
                    "remaining": -50
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].percentRemaining == 0)
    }

    // MARK: - Unlimited & Special Cases

    @Test
    func `parse unlimited plan`() throws {
        let json = """
        {
            "membershipType": "business",
            "isUnlimited": true,
            "individualUsage": {
                "plan": { "enabled": false },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].percentRemaining == 100)
        #expect(snapshot.quotas[0].resetText == "Unlimited")
        #expect(snapshot.accountTier == .custom("BUSINESS"))
    }

    @Test
    func `parse free plan`() throws {
        let json = """
        {
            "membershipType": "free",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 30,
                    "limit": 50,
                    "remaining": 20
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.accountTier == .custom("FREE"))
        #expect(snapshot.quotas.count == 1)
        #expect(abs(snapshot.quotas[0].percentRemaining - 40.0) < 0.1)
    }

    // MARK: - Error Cases

    @Test
    func `parse empty response throws error`() {
        let json = "{}".data(using: .utf8)!

        #expect(throws: ProbeError.self) {
            try CursorUsageProbe.parseUsageSummary(json)
        }
    }

    @Test
    func `parse invalid json throws error`() {
        let json = "not json".data(using: .utf8)!

        #expect(throws: ProbeError.self) {
            try CursorUsageProbe.parseUsageSummary(json)
        }
    }

    @Test
    func `parse response with no individualUsage and not unlimited throws error`() {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false
        }
        """.data(using: .utf8)!

        #expect(throws: ProbeError.self) {
            try CursorUsageProbe.parseUsageSummary(json)
        }
    }

    // MARK: - Billing Cycle

    @Test
    func `parse billing cycle end with fractional seconds`() throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "billingCycleEnd": "2025-03-01T00:00:00.000Z",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 100,
                    "limit": 500,
                    "remaining": 400
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)
        #expect(snapshot.quotas[0].resetsAt != nil)
    }

    @Test
    func `parse billing cycle end without fractional seconds`() throws {
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "billingCycleEnd": "2025-03-01T00:00:00Z",
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 100,
                    "limit": 500,
                    "remaining": 400
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)
        #expect(snapshot.quotas[0].resetsAt != nil)
    }

    // MARK: - JWT Parsing

    @Test
    func `extract user ID from valid JWT`() throws {
        // JWT with payload: {"sub": "user_abc123", "iat": 1234567890}
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let payload = "eyJzdWIiOiJ1c2VyX2FiYzEyMyIsImlhdCI6MTIzNDU2Nzg5MH0"
        let signature = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let jwt = "\(header).\(payload).\(signature)"

        let userId = try CursorUsageProbe.extractUserIdFromJWT(jwt)
        #expect(userId == "user_abc123")
    }

    @Test
    func `extract user ID with pipe character like real Cursor JWTs`() throws {
        // Cursor JWTs have sub like "github|user_01J6BBEPT2KSQKPPRGXDY8M1F4"
        // Payload: {"sub": "github|user_01ABC", "type": "session"}
        // base64url of {"sub":"github|user_01ABC","type":"session"} =
        let payloadJson = #"{"sub":"github|user_01ABC","type":"session"}"#
        let payloadBase64 = Data(payloadJson.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "eyJhbGciOiJIUzI1NiJ9.\(payloadBase64).sig"

        let userId = try CursorUsageProbe.extractUserIdFromJWT(jwt)
        #expect(userId == "github|user_01ABC")
    }

    @Test
    func `extract user ID from JWT with padding needed`() throws {
        // Payload: {"sub": "u1"}
        let header = "eyJhbGciOiJIUzI1NiJ9"
        let payload = "eyJzdWIiOiJ1MSJ9"
        let jwt = "\(header).\(payload).sig"

        let userId = try CursorUsageProbe.extractUserIdFromJWT(jwt)
        #expect(userId == "u1")
    }

    @Test
    func `extract user ID from invalid JWT throws`() {
        #expect(throws: ProbeError.self) {
            try CursorUsageProbe.extractUserIdFromJWT("not-a-jwt")
        }
    }

    @Test
    func `extract user ID from JWT without sub claim throws`() {
        // Payload: {"iat": 123} (no sub)
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJpYXQiOjEyM30.sig"

        #expect(throws: ProbeError.self) {
            try CursorUsageProbe.extractUserIdFromJWT(jwt)
        }
    }

    // MARK: - Numeric Type Handling

    @Test
    func `parse usage values as doubles`() throws {
        // Some API responses return numbers as doubles
        let json = """
        {
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": {
                "plan": {
                    "enabled": true,
                    "used": 123.0,
                    "limit": 500.0,
                    "remaining": 377.0
                },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas.count == 1)
        #expect(abs(snapshot.quotas[0].percentRemaining - 75.4) < 0.1)
    }

    // MARK: - Account Tier Detection

    @Test
    func `detect ultra tier`() throws {
        let json = """
        {
            "membershipType": "ultra",
            "isUnlimited": false,
            "individualUsage": {
                "plan": { "enabled": true, "used": 1, "limit": 40000, "remaining": 39999 },
                "onDemand": { "enabled": false, "used": 0, "limit": null, "remaining": null }
            }
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)
        #expect(snapshot.accountTier == .custom("ULTRA"))
    }
}
