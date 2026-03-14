import CryptoKit
import Foundation
import Security

struct OpenAIOAuthRequest: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

struct OpenAISubscriptionSession: Codable, Equatable {
    struct Tokens: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var idToken: String?
        var accountID: String?
        var expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case accountID = "account_id"
            case expiresAt = "expires_at"
        }
    }

    var authMode = "chatgpt"
    var tokens: Tokens
    var lastRefresh: Date
}

struct OpenAISubscriptionCredentials {
    let accessToken: String
    let accountID: String?
}

enum OpenAISubscriptionError: LocalizedError {
    case notSignedIn
    case invalidAuthorizationURL
    case invalidAuthorizationResponse
    case missingAuthorizationCode
    case stateMismatch
    case tokenExchangeFailed(String)
    case missingRefreshToken

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in with ChatGPT before using Details Description."
        case .invalidAuthorizationURL:
            return "The ChatGPT sign-in URL could not be created."
        case .invalidAuthorizationResponse:
            return "The ChatGPT sign-in flow returned an invalid callback."
        case .missingAuthorizationCode:
            return "The ChatGPT sign-in flow did not return an authorization code."
        case .stateMismatch:
            return "The ChatGPT sign-in response did not match the active login session."
        case .tokenExchangeFailed(let detail):
            return "ChatGPT sign-in failed: \(detail)"
        case .missingRefreshToken:
            return "The saved ChatGPT session cannot be refreshed. Sign in again."
        }
    }
}

@MainActor
final class OpenAISubscriptionStore: ObservableObject {
    @Published private(set) var session: OpenAISubscriptionSession?
    @Published var authRequest: OpenAIOAuthRequest?
    @Published var authErrorMessage: String?
    @Published private(set) var isAuthenticating = false

    var isSignedIn: Bool {
        session != nil
    }

    private let keychain = KeychainStore(service: "com.eyepal.openai-subscription")
    private var pendingLogin: PendingLogin?

    init() {
        session = keychain.loadSession()
    }

    func beginSignIn() {
        do {
            let pendingLogin = try PendingLogin()
            self.pendingLogin = pendingLogin
            authRequest = OpenAIOAuthRequest(url: try pendingLogin.authorizationURL())
            authErrorMessage = nil
            isAuthenticating = true
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func cancelSignIn() {
        pendingLogin = nil
        authRequest = nil
        isAuthenticating = false
    }

    func handleAuthorizationCallback(_ url: URL) {
        guard let pendingLogin else {
            authErrorMessage = OpenAISubscriptionError.invalidAuthorizationResponse.localizedDescription
            return
        }

        do {
            let callback = try AuthorizationCallback(url: url)
            guard callback.state == pendingLogin.state else {
                throw OpenAISubscriptionError.stateMismatch
            }

            authRequest = nil
            isAuthenticating = true

            Task {
                do {
                    let tokenResponse = try await exchangeAuthorizationCode(
                        code: callback.code,
                        pendingLogin: pendingLogin
                    )
                    let resolvedAccountID = tokenResponse.accountID ?? decodeAccountID(fromJWT: tokenResponse.accessToken)
                    let session = OpenAISubscriptionSession(
                        tokens: .init(
                            accessToken: tokenResponse.accessToken,
                            refreshToken: tokenResponse.refreshToken ?? "",
                            idToken: tokenResponse.idToken,
                            accountID: resolvedAccountID,
                            expiresAt: tokenResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0 - 60)) }
                        ),
                        lastRefresh: .now
                    )

                    self.session = session
                    keychain.saveSession(session)
                    self.pendingLogin = nil
                    self.isAuthenticating = false
                } catch {
                    self.authErrorMessage = error.localizedDescription
                    self.pendingLogin = nil
                    self.isAuthenticating = false
                }
            }
        } catch {
            authErrorMessage = error.localizedDescription
            cancelSignIn()
        }
    }

    func signOut() {
        session = nil
        authRequest = nil
        pendingLogin = nil
        isAuthenticating = false
        authErrorMessage = nil
        keychain.clearSession()
    }

    func activeCredentials(forceRefresh: Bool = false) async throws -> OpenAISubscriptionCredentials {
        let currentSession: OpenAISubscriptionSession
        if forceRefresh {
            currentSession = try await refreshSession()
        } else if let session, shouldRefresh(session: session) {
            currentSession = try await refreshSession()
        } else if let session {
            currentSession = session
        } else {
            throw OpenAISubscriptionError.notSignedIn
        }

        return OpenAISubscriptionCredentials(
            accessToken: currentSession.tokens.accessToken,
            accountID: currentSession.tokens.accountID
        )
    }

    private func refreshSession() async throws -> OpenAISubscriptionSession {
        guard var session else {
            throw OpenAISubscriptionError.notSignedIn
        }
        guard !session.tokens.refreshToken.isEmpty else {
            throw OpenAISubscriptionError.missingRefreshToken
        }

        let refreshedTokens = try await refreshTokens(refreshToken: session.tokens.refreshToken)
        session.tokens.accessToken = refreshedTokens.accessToken
        session.tokens.refreshToken = refreshedTokens.refreshToken ?? session.tokens.refreshToken
        session.tokens.idToken = refreshedTokens.idToken ?? session.tokens.idToken
        session.tokens.accountID = refreshedTokens.accountID
            ?? session.tokens.accountID
            ?? decodeAccountID(fromJWT: refreshedTokens.accessToken)
        session.tokens.expiresAt = refreshedTokens.expiresIn.map { Date().addingTimeInterval(TimeInterval($0 - 60)) }
        session.lastRefresh = .now

        self.session = session
        keychain.saveSession(session)
        return session
    }

    private func shouldRefresh(session: OpenAISubscriptionSession) -> Bool {
        guard let expiresAt = session.tokens.expiresAt else { return false }
        return expiresAt <= Date()
    }

    private func exchangeAuthorizationCode(
        code: String,
        pendingLogin: PendingLogin
    ) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: OpenAICodexAuthContract.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "authorization_code",
            "client_id": OpenAICodexAuthContract.clientID,
            "code": code,
            "redirect_uri": OpenAICodexAuthContract.redirectURI,
            "code_verifier": pendingLogin.codeVerifier
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateTokenResponse(data: data, response: response)
        return try JSONDecoder.openAI.decode(OAuthTokenResponse.self, from: data)
    }

    private func refreshTokens(refreshToken: String) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: OpenAICodexAuthContract.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "refresh_token",
            "client_id": OpenAICodexAuthContract.clientID,
            "refresh_token": refreshToken
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateTokenResponse(data: data, response: response)
        return try JSONDecoder.openAI.decode(OAuthTokenResponse.self, from: data)
    }

    private func validateTokenResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAISubscriptionError.tokenExchangeFailed("The authentication server returned no HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let tokenError = try? JSONDecoder.openAI.decode(TokenErrorResponse.self, from: data) {
                throw OpenAISubscriptionError.tokenExchangeFailed(tokenError.errorDescription ?? tokenError.error)
            }

            let fallback = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw OpenAISubscriptionError.tokenExchangeFailed(fallback)
        }
    }

    private func formBody(_ values: [String: String]) -> Data? {
        let body = values
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
        return body.data(using: .utf8)
    }

    private func decodeAccountID(fromJWT token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let possibleKeys = [
            "chatgpt_account_id",
            "account_id",
            "https://api.openai.com/chatgpt_account_id",
            "https://chatgpt.com/account_id"
        ]

        for key in possibleKeys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }

        return nil
    }
}

private struct OpenAICodexAuthContract {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let redirectURI = "http://localhost:1455/auth/callback"
    static let authorizationURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
}

private struct PendingLogin {
    let codeVerifier: String
    let codeChallenge: String
    let state: String

    init() throws {
        codeVerifier = Self.randomURLSafeString(byteCount: 64)
        codeChallenge = Self.makeCodeChallenge(for: codeVerifier)
        state = Self.randomURLSafeString(byteCount: 32)
    }

    func authorizationURL() throws -> URL {
        guard var components = URLComponents(url: OpenAICodexAuthContract.authorizationURL, resolvingAgainstBaseURL: false) else {
            throw OpenAISubscriptionError.invalidAuthorizationURL
        }

        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: OpenAICodexAuthContract.clientID),
            .init(name: "redirect_uri", value: OpenAICodexAuthContract.redirectURI),
            .init(name: "scope", value: "openid profile email offline_access"),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "id_token_add_organizations", value: "true"),
            .init(name: "codex_cli_simplified_flow", value: "true"),
            .init(name: "originator", value: "eyepal_ios"),
            .init(name: "state", value: state)
        ]

        guard let url = components.url else {
            throw OpenAISubscriptionError.invalidAuthorizationURL
        }
        return url
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func makeCodeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct AuthorizationCallback {
    let code: String
    let state: String

    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw OpenAISubscriptionError.invalidAuthorizationResponse
        }

        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw OpenAISubscriptionError.missingAuthorizationCode
        }
        guard let state = items.first(where: { $0.name == "state" })?.value else {
            throw OpenAISubscriptionError.invalidAuthorizationResponse
        }

        self.code = code
        self.state = state
    }
}

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: Int?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case accountID = "account_id"
    }
}

private struct TokenErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private final class KeychainStore {
    private let service: String
    private let account = "subscription-session"

    init(service: String) {
        self.service = service
    }

    func loadSession() -> OpenAISubscriptionSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return try? JSONDecoder.openAI.decode(OpenAISubscriptionSession.self, from: data)
    }

    func saveSession(_ session: OpenAISubscriptionSession) {
        guard let data = try? JSONEncoder.openAI.encode(session) else { return }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    func clearSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension JSONDecoder {
    static var openAI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var openAI: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
