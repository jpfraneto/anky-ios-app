//
//  SwipeToSealView.swift
//  Anky
//

import SwiftUI

struct SwipeToSealView: View {
    let kingdom: Kingdom
    let sessionId: String
    let onSealed: () -> Void
    let onKeepPrivate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            SealView(label: "seal") {
                onSealed()
            }

            Button {
                onKeepPrivate()
            } label: {
                Text("keep private")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.22))
            }
            .buttonStyle(.plain)
        }
    }
}
