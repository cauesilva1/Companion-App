import XCTest
@testable import Companion

final class CloudStateBundleDecodingTests: XCTestCase {
  func testDecodeCloudStateBundleWithTitlesAndProfile() throws {
    let json = """
    {
      "ok": true,
      "companion": {
        "id": "cmp-1",
        "userId": "user-1",
        "name": "Jaozinho",
        "personality": "curioso",
        "skin": "dino-mort",
        "artStyle": "pixel",
        "backdrop": "sky",
        "archetype": "zoeiro",
        "mood": "HAPPY",
        "energy": 80,
        "affection": 70,
        "lifeMode": "indoor",
        "activeTitle": "Recém-chegado",
        "titleKey": "newcomer",
        "equippedTitleKey": "newcomer"
      },
      "context": {
        "lifeMode": "indoor",
        "activeTitle": "Rei do Sofá",
        "titleKey": "sofa_king",
        "equippedTitleKey": "sofa_king",
        "mediaHint": "Lo-fi beats"
      },
      "profile": {
        "ok": true,
        "name": "Jaozinho",
        "activeTitle": "Rei do Sofá",
        "titleKey": "sofa_king",
        "equippedTitleKey": "sofa_king",
        "unlockedTitles": ["newcomer", "sofa_king"],
        "badges": [
          {
            "key": "sofa_king",
            "label": "Rei do Sofá",
            "unlocked": true,
            "equipped": true
          }
        ]
      }
    }
    """.data(using: .utf8)!

    let bundle = try XCTUnwrap(SupabaseClient.makeCloudStateBundle(from: json))
    XCTAssertEqual(bundle.snapshot.name, "Jaozinho")
    XCTAssertEqual(bundle.snapshot.activeTitle, "Rei do Sofá")
    XCTAssertEqual(bundle.snapshot.titleKey, "sofa_king")
    XCTAssertEqual(bundle.snapshot.equippedTitleKey, "sofa_king")
    XCTAssertEqual(bundle.snapshot.mediaHint, "Lo-fi beats")
    XCTAssertEqual(bundle.profile?.activeTitle, "Rei do Sofá")
    XCTAssertEqual(bundle.profile?.titleKey, "sofa_king")
    XCTAssertEqual(bundle.profile?.equippedTitleKey, "sofa_king")
    XCTAssertEqual(bundle.profile?.unlockedTitles, ["newcomer", "sofa_king"])
    XCTAssertEqual(bundle.profile?.badges?.first?.key, "sofa_king")
  }

  func testContextIngestResultDecodesTitleKeys() throws {
    let json = """
    {
      "ok": true,
      "lifeMode": "indoor",
      "activeTitle": "Night Owl",
      "titleKey": "night_owl",
      "equippedTitleKey": "night_owl",
      "energy": 55
    }
    """.data(using: .utf8)!

    let result = try JSONDecoder().decode(SupabaseClient.ContextIngestResult.self, from: json)
    XCTAssertEqual(result.activeTitle, "Night Owl")
    XCTAssertEqual(result.titleKey, "night_owl")
    XCTAssertEqual(result.equippedTitleKey, "night_owl")
    XCTAssertEqual(result.energy, 55)
  }

  func testCompanionTitlesPreferContextOverRow() throws {
    let json = """
    {
      "companion": {
        "id": "cmp-2",
        "userId": "user-2",
        "name": "Pet",
        "personality": "x",
        "skin": "dino-doux",
        "artStyle": "pixel",
        "backdrop": "sky",
        "archetype": "curioso",
        "mood": "CONTENT",
        "energy": 40,
        "affection": 40,
        "activeTitle": "Recém-chegado",
        "titleKey": "newcomer",
        "equippedTitleKey": "newcomer"
      },
      "context": {
        "activeTitle": "Gamer Noturno",
        "titleKey": "night_gamer",
        "equippedTitleKey": "night_gamer"
      }
    }
    """.data(using: .utf8)!

    let bundle = try XCTUnwrap(SupabaseClient.makeCloudStateBundle(from: json))
    XCTAssertEqual(bundle.snapshot.activeTitle, "Gamer Noturno")
    XCTAssertEqual(bundle.snapshot.titleKey, "night_gamer")
    XCTAssertEqual(bundle.snapshot.equippedTitleKey, "night_gamer")
  }

  func testMissingCompanionReturnsNilBundle() {
    let json = #"{"ok":true,"profile":{"ok":true}}"#.data(using: .utf8)!
    XCTAssertNil(SupabaseClient.makeCloudStateBundle(from: json))
  }
}
