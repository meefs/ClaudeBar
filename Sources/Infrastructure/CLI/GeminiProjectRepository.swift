import Foundation
import Domain

internal struct GeminiProjectRepository {
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval
    private static let projectsEndpoint = "https://cloudresourcemanager.googleapis.com/v1/projects"

    init(
        networkClient: any NetworkClient,
        timeout: TimeInterval
    ) {
        self.networkClient = networkClient
        self.timeout = timeout
    }

    /// Fetches the best Gemini project to use for quota checking.
    func fetchBestProject(accessToken: String) async -> GeminiProject? {
        guard let projects = await fetchProjects(accessToken: accessToken) else { return nil }
        return projects.bestProjectForQuota
    }

    /// Fetches all available Gemini projects.
    func fetchProjects(accessToken: String) async -> GeminiProjects? {
        guard let url = URL(string: Self.projectsEndpoint) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        guard let (data, response) = try? await networkClient.request(request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return try? JSONDecoder().decode(GeminiProjects.self, from: data)
    }
}
