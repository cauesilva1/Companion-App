import XCTest
@testable import Companion

/// Contratos da política anti-logout-fantasma (rede ≠ auth).
final class SessionAuthPolicyTests: XCTestCase {
  func testAuthFailuresClearTokens() {
    XCTAssertTrue(SessionAuthPolicy.shouldClearTokens(for: SupabaseError.http(401, "jwt expired")))
    XCTAssertTrue(SessionAuthPolicy.shouldClearTokens(for: SupabaseError.sessionExpired))
  }

  func testNetworkFailuresKeepTokens() {
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: URLError(.notConnectedToInternet)))
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: URLError(.timedOut)))
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: URLError(.networkConnectionLost)))
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: URLError(.cannotConnectToHost)))
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: SupabaseError.http(503, "upstream")))
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: SupabaseError.http(500, "boom")))
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: SupabaseError.http(0, "offline")))
  }

  func testNonAuthBusinessErrorsKeepTokens() {
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: SupabaseError.decoding))
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: SupabaseError.noSession))
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: SupabaseError.notConfigured))
  }

  /// Simula a decisão de wipe vs keep após saveSession (sem rede).
  func testKeychainSurvivesWhenPolicySaysKeep() async {
    let previous = await SupabaseClient.shared.loadSession()
    let marker = "unit-test-access-\(UUID().uuidString)"
    let session = SupabaseSession(
      accessToken: marker,
      refreshToken: "unit-test-refresh",
      userId: "user-unit-test",
      email: "unit@test.local",
      expiresAt: Date().timeIntervalSince1970 + 3600,
      isAnonymous: false
    )
    await SupabaseClient.shared.saveSession(session)

    let networkError: Error = URLError(.timedOut)
    XCTAssertFalse(SessionAuthPolicy.shouldClearTokens(for: networkError))

    // Em falha de rede o cliente NÃO deve chamar saveSession(nil).
    let stillThere = await SupabaseClient.shared.loadSession()
    XCTAssertEqual(stillThere?.accessToken, marker)

    // Em 401, o contrato é limpar — exercitamos explicitamente.
    if SessionAuthPolicy.shouldClearTokens(for: SupabaseError.http(401, "unauthorized")) {
      await SupabaseClient.shared.saveSession(nil)
    }
    let afterAuthWipe = await SupabaseClient.shared.loadSession()
    XCTAssertNil(afterAuthWipe)

    // Restaura sessão do desenvolvedor (se havia).
    await SupabaseClient.shared.saveSession(previous)
  }
}
