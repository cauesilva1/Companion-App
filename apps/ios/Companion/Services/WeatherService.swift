import Foundation
import CoreLocation

enum WeatherError: LocalizedError {
  case denied
  case unavailable

  var errorDescription: String? {
    switch self {
    case .denied: return "Ative a localização para o clima."
    case .unavailable: return "Não consegui sua localização."
    }
  }
}

final class LocationHelper: NSObject, CLLocationManagerDelegate {
  static let shared = LocationHelper()

  private let manager = CLLocationManager()
  private var continuation: CheckedContinuation<CLLocation, Error>?

  private override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyKilometer
  }

  func request() async throws -> CLLocation {
    try await withCheckedThrowingContinuation { cont in
      self.continuation = cont
      let status = manager.authorizationStatus
      switch status {
      case .notDetermined:
        manager.requestWhenInUseAuthorization()
      case .denied, .restricted:
        cont.resume(throwing: WeatherError.denied)
        continuation = nil
      default:
        manager.requestLocation()
      }
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard continuation != nil else { return }
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      manager.requestLocation()
    case .denied, .restricted:
      continuation?.resume(throwing: WeatherError.denied)
      continuation = nil
    default:
      break
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let cont = continuation else { return }
    if let loc = locations.first {
      cont.resume(returning: loc)
    } else {
      cont.resume(throwing: WeatherError.unavailable)
    }
    continuation = nil
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}

enum WeatherService {
  struct Snapshot: Sendable {
    var city: String
    var region: String
    var tempC: Int
    var description: String
  }

  private static var cached: (Snapshot, Date)?
  private static let cacheTTL: TimeInterval = 10 * 60

  private static let wmo: [Int: String] = [
    0: "céu limpo", 1: "principalmente limpo", 2: "parcialmente nublado", 3: "nublado",
    45: "neblina", 48: "neblina gelada", 51: "garoa fraca", 53: "garoa", 55: "garoa forte",
    61: "chuva fraca", 63: "chuva", 65: "chuva forte", 71: "neve fraca", 73: "neve",
    75: "neve forte", 80: "pancadas fracas", 81: "pancadas", 82: "pancadas fortes",
    95: "trovoada", 96: "trovoada com granizo", 99: "trovoada forte",
  ]

  static func isWeatherQuestion(_ message: String) -> Bool {
    message.range(
      of: #"temperatura|tempo|clima|graus|°\s*c|faz\s+calor|faz\s+frio|chove|chuva|umidade|como\s+est[aá]\s+o\s+tempo|weather"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  }

  static func snapshot() async throws -> Snapshot {
    if let cached, Date().timeIntervalSince(cached.1) < cacheTTL {
      return cached.0
    }
    let location = try await LocationHelper.shared.request()
    let lat = location.coordinate.latitude
    let lon = location.coordinate.longitude

    let weatherURL = URL(string:
      "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&timezone=auto"
    )!
    let (data, _) = try await URLSession.shared.data(from: weatherURL)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let current = json?["current"] as? [String: Any]
    let tempDouble = current?["temperature_2m"] as? Double
    let tempInt = current?["temperature_2m"] as? Int
    let temp = tempDouble ?? Double(tempInt ?? 0)
    let code = (current?["weather_code"] as? Int) ?? 0

    var city = "sua região"
    var region = ""
    if let placemark = try? await reverseGeocode(location) {
      city = placemark.locality ?? placemark.name ?? city
      region = placemark.administrativeArea ?? ""
    }

    let snap = Snapshot(
      city: city,
      region: region,
      tempC: Int(temp.rounded()),
      description: wmo[code] ?? "tempo indefinido"
    )
    cached = (snap, Date())
    return snap
  }

  private static func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark? {
    try await withCheckedThrowingContinuation { cont in
      CLGeocoder().reverseGeocodeLocation(location) { marks, error in
        if let error {
          cont.resume(throwing: error)
        } else {
          cont.resume(returning: marks?.first)
        }
      }
    }
  }

  static func contextLine(_ snap: Snapshot) -> String {
    "\(snap.city), \(snap.region.isEmpty ? "" : "\(snap.region), ")\(snap.tempC)°C, \(snap.description)"
  }
}
