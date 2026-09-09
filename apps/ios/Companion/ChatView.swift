import SwiftUI

/// Chat dedicado — estilo conversa (avatar + balão), campo + Enviar.
struct ChatView: View {
  @ObservedObject var model: CompanionViewModel
  @FocusState private var focused: Bool
  @Environment(\.dismiss) private var dismiss

  private var turns: [ChatTurn] {
    model.chatHistory
  }

  var body: some View {
    ZStack {
      CompanionTheme.screenBackground
      VStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
              ForEach(turns) { turn in
                bubble(turn)
                  .id(turn.id)
              }
              if model.isBusy {
                typingRow
                  .id("typing")
              }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .onChange(of: turns.count) { _ in
            scrollToBottom(proxy)
          }
          .onChange(of: model.isBusy) { _ in
            scrollToBottom(proxy)
          }
          .onAppear {
            scrollToBottom(proxy)
          }
        }

        Divider().overlay(Color.black.opacity(0.08))
        HStack(alignment: .bottom, spacing: 10) {
          TextField("Mensagem…", text: $model.chatText, axis: .vertical)
            .lineLimit(1...4)
            .focused($focused)
            .foregroundStyle(CompanionTheme.title)
            .submitLabel(.send)
            .onSubmit { Task { await send() } }
            .padding(12)
            .background(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
            )

          Button {
            Task { await send() }
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.system(size: 34))
              .foregroundStyle(
                canSend ? CompanionTheme.play : Color.gray.opacity(0.35)
              )
          }
          .buttonStyle(.plain)
          .disabled(!canSend)
          .accessibilityLabel("Enviar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.96))
      }
    }
    .preferredColorScheme(.light)
    .navigationTitle("Conversar")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Color.white.opacity(0.95), for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarColorScheme(.light, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Fechar") {
          focused = false
          dismiss()
        }
        .foregroundStyle(CompanionTheme.play)
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

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    if model.isBusy {
      withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
    } else if let last = turns.last {
      withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
    }
  }

  private var typingRow: some View {
    HStack(alignment: .top, spacing: 10) {
      DinoStaticFrame(skin: model.snapshot.skin, size: 34)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      Text("\(model.snapshot.name) está digitando…")
        .font(.caption)
        .foregroundStyle(CompanionTheme.subtitle)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        )
      Spacer(minLength: 36)
    }
  }

  @ViewBuilder
  private func bubble(_ turn: ChatTurn) -> some View {
    if turn.isUser {
      HStack(alignment: .top, spacing: 8) {
        Spacer(minLength: 48)
        Text(turn.text)
          .font(.body)
          .foregroundStyle(Color.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(CompanionTheme.play)
          )
      }
    } else {
      HStack(alignment: .top, spacing: 10) {
        DinoStaticFrame(skin: model.snapshot.skin, size: 34)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(Color.black.opacity(0.06), lineWidth: 1)
          )
          .accessibilityLabel(model.snapshot.name)

        VStack(alignment: .leading, spacing: 4) {
          Text(model.snapshot.name)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CompanionTheme.subtitle)
          Text(turn.text)
            .font(.body)
            .foregroundStyle(CompanionTheme.title)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.07), radius: 5, y: 2)
            )
        }
        Spacer(minLength: 36)
      }
    }
  }
}

struct ChatTurn: Identifiable {
  let id: String
  let isUser: Bool
  let text: String
  var createdAt: Date = Date()
}

struct MissionsSheet: View {
  @ObservedObject var model: CompanionViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        CompanionTheme.screenBackground
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            Text(MissionCatalog.displayDayLabel())
              .font(.caption.weight(.semibold))
              .foregroundStyle(CompanionTheme.subtitle)
              .padding(.horizontal, 4)
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
      .toolbarBackground(Color.white.opacity(0.95), for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarColorScheme(.light, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Fechar") { dismiss() }
            .foregroundStyle(CompanionTheme.play)
        }
      }
    }
  }
}
