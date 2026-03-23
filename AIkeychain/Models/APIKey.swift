import Foundation

struct APIKey: Identifiable, Hashable {
    let id: UUID
    let service: ServiceType
    var envVarName: String
    var isConfigured: Bool

    init(id: UUID = UUID(), service: ServiceType, envVarName: String? = nil, isConfigured: Bool = false) {
        self.id = id
        self.service = service
        self.envVarName = envVarName ?? service.envVarName
        self.isConfigured = isConfigured
    }
}
