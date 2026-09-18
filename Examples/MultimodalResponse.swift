import AppleAgentKit
import CoreGraphics

@Generable
struct ImageAnalysis {
    let summary: String
    let objects: [String]
}

func analyze(
    image: CGImage,
    using model: some LanguageModel
) async throws -> ImageAnalysis {
    let session = LanguageModelSession(model: model)

    let response = try await session.respond(
        generating: ImageAnalysis.self
    ) {
        "Analyze this image."
        Attachment(image)
    }

    return response.content
}
