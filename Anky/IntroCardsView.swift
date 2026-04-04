//
//  IntroCardsView.swift
//  Anky
//

import SwiftUI

// MARK: - Intro Cards (8 chakra-colored screens)

struct IntroCardsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private static let dismissedKey = "anky.intro_cards_dismissed"

    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
    }

    static func markDismissed() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    var body: some View {
        ZStack {
            cards[currentPage].color
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: currentPage)

            VStack(spacing: 0) {
                // Page dots
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? Color.white : Color.white.opacity(0.25))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 60)

                Spacer()

                // Icon
                Text(cards[currentPage].icon)
                    .font(.system(size: 48))
                    .padding(.bottom, 24)

                // Title
                Text(cards[currentPage].title)
                    .font(.ankyBody(26))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                // Body
                Text(cards[currentPage].body)
                    .font(.ankyBody(16))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
                    .padding(.top, 16)

                Spacer()
                Spacer()

                // Action
                if currentPage < 7 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            currentPage += 1
                        }
                    } label: {
                        Text("siguiente")
                            .font(.ankyLabel(16, weight: .medium))
                            .foregroundStyle(cards[currentPage].color)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    Button("saltar") {
                        dismiss()
                    }
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                } else {
                    // Last card: "don't show again"
                    Button {
                        Self.markDismissed()
                        dismiss()
                    } label: {
                        Text("no mostrar de nuevo")
                            .font(.ankyLabel(16, weight: .medium))
                            .foregroundStyle(cards[currentPage].color)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    Button("cerrar") {
                        dismiss()
                    }
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }

                Spacer()
                    .frame(height: 40)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width < -40, currentPage < 7 {
                        withAnimation(.easeInOut(duration: 0.4)) { currentPage += 1 }
                    } else if value.translation.width > 40, currentPage > 0 {
                        withAnimation(.easeInOut(duration: 0.4)) { currentPage -= 1 }
                    }
                }
        )
        .statusBarHidden(true)
    }

    // MARK: - Card Data

    private struct CardData {
        let color: Color
        let icon: String
        let title: String
        let body: String
    }

    private let cards: [CardData] = [
        // 1 — Root (Red) — What is Anky
        CardData(
            color: Color(hex: "8B1A1A"),
            icon: "🔴",
            title: "esto es anky",
            body: "un espacio para escribir sin filtros. sin juicio. sin editar. solo tú y tus palabras."
        ),
        // 2 — Sacral (Orange) — The 8-minute rule
        CardData(
            color: Color(hex: "C2540A"),
            icon: "🟠",
            title: "8 minutos",
            body: "cada sesión dura 8 minutos. ese es el tiempo que necesitas para llegar al otro lado de tu mente."
        ),
        // 3 — Solar Plexus (Yellow) — The 8-second rule
        CardData(
            color: Color(hex: "9A7B0F"),
            icon: "🟡",
            title: "8 segundos",
            body: "si dejas de escribir por 8 segundos, la sesión muere. no pienses. no pares. deja que fluya."
        ),
        // 4 — Heart (Green) — No deleting
        CardData(
            color: Color(hex: "2D6A4F"),
            icon: "🟢",
            title: "sin borrar",
            body: "no puedes borrar lo que escribes. cada palabra se queda. eso es lo que lo hace real."
        ),
        // 5 — Throat (Blue) — Your writing becomes stories
        CardData(
            color: Color(hex: "1B4965"),
            icon: "🔵",
            title: "tus palabras crean cuentos",
            body: "lo que escribes se transforma en historias narradas. tu subconsciente, convertido en arte."
        ),
        // 6 — Third Eye (Indigo) — The anky
        CardData(
            color: Color(hex: "312E81"),
            icon: "🟣",
            title: "el anky",
            body: "si llegas a los 8 minutos sin parar, nace un anky. una pieza única que viene de lo más profundo de ti."
        ),
        // 7 — Crown (Violet) — Your identity
        CardData(
            color: Color(hex: "581C87"),
            icon: "👁️",
            title: "tu identidad es tuya",
            body: "tu cuenta vive en tu dispositivo. 12 palabras la protegen. nadie más tiene acceso. ni siquiera nosotros."
        ),
        // 8 — Unity (White/Clear) — Begin
        CardData(
            color: Color(hex: "1C1C2E"),
            icon: "✨",
            title: "estás listo",
            body: "no hay reglas más allá de estas. cierra los ojos. respira. y cuando estés listo, escribe."
        ),
    ]
}
