//
//  SessionDetailSheet.swift
//  Anky
//

import SwiftUI
import UIKit

struct SessionDetailSheet: View {
    let entry: CachedWritingEntry
    var onContinueConversation: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var kingdomColor: Color {
        entry.ankyKingdom?.color ?? AnkyKingdom.unclassifiedColor
    }

    private var fullDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: entry.createdAt)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Handle bar
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "2a1a4a"))
                        .frame(width: 36, height: 3)
                    Spacer()
                }
                .padding(.top, 12)

                // MARK: - Image area
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            RadialGradient(
                                colors: [kingdomColor.opacity(0.35), kingdomColor.opacity(0.05)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 140
                            )
                        )
                        .frame(height: 180)

                    // Center circle with anky image
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color(hex: "1e6eb5"), Color(hex: "0a1a3a")],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 36
                                    )
                                )
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Circle()
                                        .stroke(kingdomColor, lineWidth: 1.5)
                                )

                            if let url = entry.remoteImageURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 68, height: 68)
                                            .clipShape(Circle())
                                    default:
                                        Text("\u{1F98B}")
                                            .font(.system(size: 32))
                                    }
                                }
                            } else {
                                Text("\u{1F98B}")
                                    .font(.system(size: 32))
                            }
                        }
                        Spacer()
                    }

                    // Bottom-left overlay: energy + date
                    VStack(alignment: .leading, spacing: 2) {
                        Text((entry.energy ?? "unclassified").uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(kingdomColor)
                        Text(fullDateLabel.uppercased())
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(kingdomColor)
                    }
                    .padding(10)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // MARK: - Anky's reflection
                VStack(alignment: .leading, spacing: 8) {
                    Text("anky's reflection".uppercased())
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "333333"))
                        .tracking(2)

                    if let response = entry.response {
                        Text(response)
                            .font(.custom("Georgia", size: 14))
                            .italic()
                            .foregroundColor(Color(hex: "9d9488"))
                            .lineSpacing(12)
                    } else {
                        Text("reflection pending...")
                            .font(.custom("Georgia", size: 14))
                            .italic()
                            .foregroundColor(Color(hex: "9d9488").opacity(0.5))
                            .lineSpacing(12)
                    }
                }

                // MARK: - Why [kingdom] card
                if let kingdom = entry.kingdom, let reason = entry.reason {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("why \(kingdom)".uppercased())
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "333333"))
                            .tracking(2)

                        Text(reason)
                            .font(.system(size: 12))
                            .italic()
                            .foregroundColor(Color(hex: "555555"))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(kingdomColor, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            )
                    }
                }

                // MARK: - Kingdom lesson card
                if let ankyKingdom = entry.ankyKingdom {
                    Text(ankyKingdom.lesson)
                        .font(.system(size: 12))
                        .italic()
                        .foregroundColor(kingdomColor)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(kingdomColor.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(kingdomColor.opacity(0.13), lineWidth: 1)
                        )
                }

                // MARK: - What you wrote
                VStack(alignment: .leading, spacing: 8) {
                    Text("what you wrote".uppercased())
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "333333"))
                        .tracking(2)

                    ScrollView {
                        Text(entry.content)
                            .font(.ankyMono(13))
                            .foregroundColor(Color(hex: "555555"))
                            .lineSpacing(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "080612"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "1a1030"), lineWidth: 1)
                    )
                }

                // MARK: - Stats row
                HStack(spacing: 12) {
                    Text("\(entry.wordCount) words")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "444444"))

                    if let flowScore = entry.flowScore {
                        Text("\(Int(flowScore * 100))% flow")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "444444"))
                    }

                    Spacer()

                    if entry.isAnky {
                        Text("\u{2726} complete")
                            .font(.system(size: 11))
                            .foregroundColor(kingdomColor)
                    } else {
                        Text("\u{25E6} incomplete")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "444444"))
                    }
                }

                // MARK: - Continue conversation button
                if entry.ankyId != nil {
                    Button {
                        onContinueConversation?()
                        dismiss()
                    } label: {
                        Text("continue this conversation \u{2192}")
                            .font(.system(size: 13))
                            .foregroundColor(kingdomColor)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(kingdomColor.opacity(0.09))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(kingdomColor.opacity(0.27), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(hex: "080612"))
        .presentationDetents([.fraction(0.85)])
        .presentationDragIndicator(.hidden)
    }
}
