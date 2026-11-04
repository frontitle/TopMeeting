import Foundation
import CryptoKit

enum SummaryProviderKind: String, Codable, CaseIterable, Identifiable {
    case openClaw = "openclaw", compatible = "openai-compatible"
    var id: String { rawValue }
    var title: String { self == .openClaw ? "OpenClaw" : "OpenAI-compatible API" }
    var baseKey: String { self == .openClaw ? "gateway" : "compatibleGateway" }
    var modelKey: String { self == .openClaw ? "agent" : "compatibleModel" }
    var credentialAccount: String { self == .openClaw ? "token" : "compatible-token" }
}
struct SummaryConnection {
    let kind: SummaryProviderKind
    let base: String
    let token: String
    let model: String
    var cacheKey: String {
        SHA256.hash(data:Data((kind.rawValue+"\n"+base+"\n"+model).utf8)).map { String(format:"%02x",$0) }.joined()
    }
}
@MainActor protocol SummaryProvider {
    func stream(connection: SummaryConnection,meeting: Meeting,mode: MeetingRequest,delta: @escaping @MainActor (String) -> Void) async throws
}
struct ChatCompletionsProvider: SummaryProvider {
    func stream(connection: SummaryConnection,meeting: Meeting,mode: MeetingRequest,delta: @escaping @MainActor (String) -> Void) async throws {
        try await Gateway.stream(base:connection.base,token:connection.token,agent:connection.model,meeting:meeting,mode:mode,provider:connection.kind,delta:delta)
    }
}
/// Document delivery is independent of recognition and the model provider.
/// Future message-based connectors (e.g. Slack) may expose a different capability.
protocol DocumentConnector {
    func status() async throws -> Bool
    func login() async throws -> (URL,String)
    func finishLogin(code: String) async throws
    func create(title: String) async throws -> FeishuDocument
    func append(document: String,xml: String) async throws
    func attach(document: String,path: String) async throws
}
extension FeishuCLI: DocumentConnector {}
