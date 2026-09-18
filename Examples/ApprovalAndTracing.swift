import AppleAgentKit

func makeTracer(
    traceURL: URL
) -> AgentTracer {
    let memory = MemoryTraceSink()
    let file = JSONLTraceSink(fileURL: traceURL)

    return AgentTracer(
        sinks: [
            memory,
            file
        ]
    )
}

let approval = ClosureApprovalHandler { call in
    // Present UI or apply application policy here.
    print("Approval requested for:", call.toolName)
    return true
}
