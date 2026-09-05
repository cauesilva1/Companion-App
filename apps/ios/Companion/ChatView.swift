import SwiftUI

/// Chat dedicado — campo + Enviar + teclado fecha após send.
struct ChatView: View {
  @ObservedObject var model: CompanionViewModel
  @FocusState private var focused: Bool
  @Environment(\.dismiss) private var dismiss

  private var turns: [ChatTurn] {
    model.chatHistory
  }

  var body: some View {
    ZStack {
      SkyBackground(artOpacity: 0.2)
      VStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
              ForEach(turns) { turn in
                bubble(turn)
                  .id(turn.id)
              }
            }
            .padding(16)
          }
          .onChange(of: turns.count) { _ in
            if let last = turns.last {
              withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
          }
          .onAppear {
            if let last = turns.last {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        }

        Divider()
        HStack(alignment: .bottom, spacing: 10) {
          TextField("Mensagem…", text: $model.chatText, axis: .vertical)
            .lineLimit(1...4)
            .focused($focused)
            .submitLabel(.send)
            .onSubmit { Task { await send() } }
            .padding(12)
            .background(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.94, green: 0.96, blue: 1.0))
            )

          Button {
            Task { await send() }
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.system(size: 34))
              .foregroundStyle(
                canSend ? CompanionTheme.play : Color.gray.opacity(0.4)
              )
          }
          .buttonStyle(.plain)
          .disabled(!canSend)
          .accessibilityLabel("Enviar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
      }
    }
    .preferredColorScheme(.light)
    .navigationTitle("Conversar")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Fechar") {
          focused = false
          dismiss()
        }
      }
    }
    .onAppear { focused = true }
  }

  private var canSend: Bool {
    !model.isBusy && !model.chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func send() async {
    guard canSend else { return }
    focused = false
    await model.interact("CHAT")
  }

  @ViewBuilder
  private func bubble(_ turn: ChatTurn) -> some View {
    HStack {
      if turn.isUser { Spacer(minLength: 40) }
      VStack(alignment: turn.isUser ? .trailing : .leading, spacing: 4) {
        Text(turn.isUser ? "Você" : model.snapshot.name)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(CompanionTheme.subtitle)
        Text(turn.text)
          .font(.body)
          .foregroundStyle(CompanionTheme.title)
          .padding(12)
          .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(turn.isUser ? CompanionTheme.play.opacity(0.18) : Color.white.opacity(0.92))
          )
      }
      if !turn.isUser { Spacer(minLength: 40) }
    }
  }
}

struct ChatTurn: Identifiable {
  let id: String
  let isUser: Bool
  let text: String
}

struct MissionsSheet: View {
  @ObservedObject var model: CompanionViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        SkyBackground(artOpacity: 0.18)
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(model.missions) { mission in
              CompanionCard {
                VStack(alignment: .leading, spacing: 8) {
                  Text(mission.title)
                    .font(.headline)
                    .foregroundStyle(CompanionTheme.title)
                  Text(mission.description)
                    .font(.caption)
                    .foregroundStyle(CompanionTheme.subtitle)
                  ProgressView(
                    value: Double(min(mission.progress, mission.target)),
                    total: Double(max(mission.target, 1))
                  )
                  .tint(CompanionTheme.play)
                  HStack {
                    Text("\(mission.progress)/\(mission.target)")
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(CompanionTheme.subtitle)
                    Spacer()
                    if mission.claimed {
                      Text("Feito")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CompanionTheme.play)
                    } else if mission.complete {
                      Button("Resgatar") {
                        Task { await model.claimMission(mission) }
                      }
                      .font(.subheadline.weight(.bold))
                      .tint(CompanionTheme.feed)
                    }
                  }
                }
              }
            }
          }
          .padding(16)
        }
      }
      .preferredColorScheme(.light)
      .navigationTitle("Missões")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Fechar") { dismiss() }
        }
      }
    }
  }
}
