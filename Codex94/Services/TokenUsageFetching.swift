protocol TokenUsageFetching: Sendable {
    func fetchUsage(executable: LocatedCodex) async throws -> TokenUsageSnapshot
    func shutdown()
}

extension TokenUsageFetching {
    func shutdown() {}
}
