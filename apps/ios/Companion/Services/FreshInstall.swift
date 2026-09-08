import Foundation

/// iOS mantém o Keychain após desinstalar o app (mesmo bundle id).
/// UserDefaults some — usamos isso para detectar “instalação nova” e limpar tokens fantasmas.
enum FreshInstall {
  private static let launchedKey = "companion.didLaunch.v1"

  /// Chamar no boot, antes de bootstrap/Spotify.
  static func resetKeychainIfReinstalled() {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: launchedKey) { return }

    // Primeira abertura desta instalação → Keychain antigo some.
    KeychainStore.clearAll()
    defaults.set(true, forKey: launchedKey)
  }
}
