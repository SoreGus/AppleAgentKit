import AppleAgentKit

@Generable
struct SearchArguments {
    @Guide(description: "Search query.")
    let query: String
}

@Generable
struct SearchResult {
    let title: String
    let summary: String
}

struct SearchTool: Tool {
    let name = "search"
    let description = "Searches a knowledge source."

    func call(
        arguments: SearchArguments
    ) async throws -> String {
        "Result for: \(arguments.query)"
    }
}
