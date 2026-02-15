import Testing
@testable import Infrastructure
@testable import Domain

@Suite("CursorUsageProbe Parsing Tests")
struct CursorUsageProbeParsingTests {

    // MARK: - Usage Summary Parsing

    @Test
    func `parse pro plan with plan usage`() throws {
        let json = """
        {
            "membershipType": "pro",
            "planUsage": {
                "enabled": true,
                "used": 123,
                "limit": 500,
                "remaining": 377,
                "percentUsed": 24.6
            },
            "billingCycleStart": "2025-01-01T00:00:00Z",
            "billingCycleEnd": "2025-02-01T00:00:00Z",
            "isUnlimited": false
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
    func `parse plan with on-demand usage`() throws {
        let json = """
        {
            "membershipType": "pro",
            "planUsage": {
                "enabled": true,
                "used": 400,
                "limit": 500,
                "remaining": 100
            },
            "onDemandUsage": {
                "enabled": true,
                "used": 25,
                "limit": 100
            },
            "isUnlimited": false
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
    func `parse unlimited plan`() throws {
        let json = """
        {
            "membershipType": "business",
            "planUsage": {
                "enabled": false
            },
            "isUnlimited": true
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].percentRemaining == 100)
        #expect(snapshot.quotas[0].resetText == "Unlimited")
        #expect(snapshot.accountTier == .custom("BUSINESS"))
    }

    @Test
    func `parse depleted plan usage`() throws {
        let json = """
        {
            "membershipType": "pro",
            "planUsage": {
                "enabled": true,
                "used": 500,
                "limit": 500,
                "remaining": 0
            },
            "isUnlimited": false
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
            "planUsage": {
                "enabled": true,
                "used": 550,
                "limit": 500,
                "remaining": -50
            },
            "isUnlimited": false
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].percentRemaining == 0)
    }

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
    func `parse free plan`() throws {
        let json = """
        {
            "membershipType": "free",
            "planUsage": {
                "enabled": true,
                "used": 30,
                "limit": 50,
                "remaining": 20
            },
            "isUnlimited": false
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.accountTier == .custom("FREE"))
        #expect(snapshot.quotas.count == 1)
        #expect(abs(snapshot.quotas[0].percentRemaining - 40.0) < 0.1)
    }

    @Test
    func `parse billing cycle end with fractional seconds`() throws {
        let json = """
        {
            "membershipType": "pro",
            "planUsage": {
                "enabled": true,
                "used": 100,
                "limit": 500,
                "remaining": 400
            },
            "billingCycleEnd": "2025-03-01T00:00:00.000Z",
            "isUnlimited": false
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas[0].resetsAt != nil)
    }

    @Test
    func `parse with disabled plan usage but unlimited flag`() throws {
        let json = """
        {
            "membershipType": "pro",
            "planUsage": {
                "enabled": false
            },
            "isUnlimited": true
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].percentRemaining == 100)
        #expect(snapshot.quotas[0].resetText == "Unlimited")
    }

    // MARK: - JWT Parsing

    @Test
    func `extract user ID from valid JWT`() throws {
        // JWT with payload: {"sub": "user_abc123", "iat": 1234567890}
        // Header: {"alg": "HS256", "typ": "JWT"}
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let payload = "eyJzdWIiOiJ1c2VyX2FiYzEyMyIsImlhdCI6MTIzNDU2Nzg5MH0"
        let signature = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let jwt = "\(header).\(payload).\(signature)"

        let userId = try CursorUsageProbe.extractUserIdFromJWT(jwt)
        #expect(userId == "user_abc123")
    }

    @Test
    func `extract user ID from JWT with padding needed`() throws {
        // Payload that needs base64 padding: {"sub": "u1"}
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
            "planUsage": {
                "enabled": true,
                "used": 123.0,
                "limit": 500.0,
                "remaining": 377.0
            },
            "isUnlimited": false
        }
        """.data(using: .utf8)!

        let snapshot = try CursorUsageProbe.parseUsageSummary(json)

        #expect(snapshot.quotas.count == 1)
        #expect(abs(snapshot.quotas[0].percentRemaining - 75.4) < 0.1)
    }
}
