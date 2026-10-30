import Foundation

struct AccountSession: Equatable, Sendable {
    let displayName: String
    let email: String?
}

@MainActor
final class AccountViewModel: ObservableObject {
    @Published var isLoginSheetPresented = false
    @Published private(set) var session: AccountSession?
    @Published private(set) var isLoggingIn = false
    @Published private(set) var errorMessage: String?

    private let api: MojiAPIClient

    init(api: MojiAPIClient = .shared) {
        self.api = api
        if let persisted = AccountSessionStore.load() {
            Task {
                await api.restoreSession(
                    token: persisted.sessionToken,
                    deviceID: persisted.deviceID
                )
                session = AccountSession(
                    displayName: persisted.displayName,
                    email: persisted.email
                )
            }
        }
    }

    @discardableResult
    func login(email: String, password: String) async -> Bool {
        guard !isLoggingIn else { return false }
        isLoggingIn = true
        errorMessage = nil
        defer { isLoggingIn = false }

        do {
            let response = try await api.login(email: email, password: password)
            let normalizedEmail = response.user.email?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let name = response.user.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = [name, normalizedEmail]
                .compactMap { $0 }
                .first(where: { !$0.isEmpty })
                ?? "已登录"
            let accountSession = AccountSession(
                displayName: displayName,
                email: normalizedEmail
            )
            let deviceID = await api.deviceIdentifier()
            do {
                try AccountSessionStore.save(
                    PersistedAccountSession(
                        sessionToken: response.sessionToken,
                        deviceID: deviceID,
                        displayName: displayName,
                        email: normalizedEmail
                    )
                )
            } catch {
                await api.logout()
                throw error
            }
            session = accountSession
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logout() {
        errorMessage = nil
        AccountSessionStore.delete()
        Task {
            await api.logout()
            session = nil
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
