import Testing
import Foundation
import Mockable
@testable import Infrastructure

@Suite
struct GeminiProjectRepositoryTests {
    
    @Test
    func `fetchProjects returns nil when network fails`() async throws {
        let mockService = MockNetworkClient()
        given(mockService)
            .request(.any)
            .willProduce { _ in throw URLError(.notConnectedToInternet) }
        
        let repository = GeminiProjectRepository(
            networkClient: mockService,
            timeout: 1.0
        )
        
        let projects = await repository.fetchProjects(accessToken: "token")
        #expect(projects == nil)
    }
    
    @Test
    func `fetchProjects parses projects and returns collection`() async throws {
        let mockService = MockNetworkClient()
        let json = """
        {
            "projects": [
                { "projectId": "gen-lang-client-123", "labels": {} },
                { "projectId": "other-project", "labels": {"generative-language": "true"} }
            ]
        }
        """.data(using: .utf8)!
        
        given(mockService)
            .request(.any)
            .willReturn((json, HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        
        let repository = GeminiProjectRepository(
            networkClient: mockService,
            timeout: 1.0
        )
        
        let projects = await repository.fetchProjects(accessToken: "token")
        
        #expect(projects != nil)
        #expect(projects?.projects.count == 2)
    }
    
    @Test
    func `fetchBestProject returns correct project`() async throws {
        let mockService = MockNetworkClient()
        let json = """
        {
            "projects": [
                { "projectId": "other-project", "labels": {"generative-language": "true"} },
                { "projectId": "gen-lang-client-123", "labels": {} }
            ]
        }
        """.data(using: .utf8)!
        
        given(mockService)
            .request(.any)
            .willReturn((json, HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        
        let repository = GeminiProjectRepository(
            networkClient: mockService,
            timeout: 1.0
        )
        
        let project = await repository.fetchBestProject(accessToken: "token")
        
        #expect(project?.projectId == "gen-lang-client-123")
    }
}