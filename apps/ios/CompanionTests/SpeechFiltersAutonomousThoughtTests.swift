import XCTest
@testable import Companion

final class SpeechFiltersAutonomousThoughtTests: XCTestCase {
  func testBlocksStatusEnvironmentLogs() {
    XCTAssertTrue(SpeechFilters.isStatusEnvironmentLog("Tô no sofá"))
    XCTAssertTrue(SpeechFilters.isStatusEnvironmentLog("Deitado aqui no sofá, TV ligada"))
    XCTAssertTrue(SpeechFilters.isStatusEnvironmentLog("Xbox offline, energia 40%"))
    XCTAssertTrue(SpeechFilters.isStatusEnvironmentLog("Modo sofá + regenerando"))

    XCTAssertFalse(SpeechFilters.acceptAutonomousThought("Tô no sofá"))
    XCTAssertFalse(SpeechFilters.acceptAutonomousThought("Sofá, TV ligada e Xbox offline"))
  }

  func testBlocksPromptLeakAndHardwareNoise() {
    XCTAssertTrue(SpeechFilters.isPromptLeak("LifeMode: indoor Traits: zoeiro"))
    XCTAssertTrue(SpeechFilters.isPromptLeak("Here's a thinking process: analyze user"))
    XCTAssertTrue(SpeechFilters.isPromptLeak("System: gere uma micro-história"))
    XCTAssertFalse(SpeechFilters.acceptAutonomousThought("Thinking process: analyze user mood"))
  }

  func testAcceptsNaturalGeekThought() {
    XCTAssertTrue(
      SpeechFilters.acceptAutonomousThought("Se o boss desse XP por procrastinar, eu já era lendário.")
    )
    XCTAssertTrue(
      SpeechFilters.acceptAutonomousThought("Tô imaginando um patch note só pra gente.")
    )
  }

  func testLocalVoiceAutonomousThoughtPassesFilterWhenNatural() {
    let line = LocalVoice.autonomousThought(
      name: "Jaozinho",
      archetype: "zoeiro",
      mood: "HAPPY",
      energy: 70,
      zoneName: nil,
      traits: nil,
      lifeMode: "indoor",
      gamingStatus: nil,
      mediaHint: nil
    )
    // Pool local pode ocasionalmente gerar curtos; o contrato crítico é o filtro.
    if SpeechFilters.isStatusEnvironmentLog(line) || SpeechFilters.isPromptLeak(line) {
      XCTFail("LocalVoice gerou log de status/prompt: \(line)")
    }
  }
}
