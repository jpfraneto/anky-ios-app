//
//  OnboardingRitualView.swift
//  Anky
//
//  The first-run onboarding is a ritual, not a tutorial.
//  One world, one character, one mission: write for 8 minutes.
//  Happens exactly once. After the first real anky persists, the app unlocks forever.
//

import Combine
import SwiftUI
import UIKit

// MARK: - Onboarding Phase State Machine

enum OnboardingPhase: Int, Equatable {
    case ember = 0
    case invitation = 1
    case writing = 2
    case shortSessionEnd = 3
    case arrival = 4
    case unlock = 5
}

// MARK: - Onboarding Copy (localized)

private struct OnboardingCopy {
    static var current: OnboardingCopy { OnboardingCopy(lang: resolvedLanguage()) }

    let lang: String

    var emberLine: String { translations[lang]?["ember"] ?? translations["en"]!["ember"]! }
    var writeLine1: String { translations[lang]?["write1"] ?? translations["en"]!["write1"]! }
    var writeLine2: String { translations[lang]?["write2"] ?? translations["en"]!["write2"]! }
    var writeLine3: String { translations[lang]?["write3"] ?? translations["en"]!["write3"]! }
    var beginAction: String { translations[lang]?["begin"] ?? translations["en"]!["begin"]! }
    var arrivalLine: String { translations[lang]?["arrival"] ?? translations["en"]!["arrival"]! }
    var notYet: String { translations[lang]?["notYet"] ?? translations["en"]!["notYet"]! }
    var tryAgain: String { translations[lang]?["tryAgain"] ?? translations["en"]!["tryAgain"]! }
    var eightMinutes: String { translations[lang]?["eightMin"] ?? translations["en"]!["eightMin"]! }

    private static func resolvedLanguage() -> String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let normalized = preferred.replacingOccurrences(of: "_", with: "-")
        return normalized.split(separator: "-").first.map(String.init) ?? "en"
    }

    private let translations: [String: [String: String]] = [
        "en": [
            "ember": "i've been waiting for you.",
            "write1": "write for 8 minutes.",
            "write2": "don't stop for 8 seconds.",
            "write3": "reach the end and i wake up.",
            "begin": "begin",
            "arrival": "you found me.",
            "notYet": "not yet.",
            "tryAgain": "try again",
            "eightMin": "(8 minutes)",
        ],
        "es": [
            "ember": "te estaba esperando.",
            "write1": "escribe por 8 minutos.",
            "write2": "no pares por 8 segundos.",
            "write3": "llega al final y despierto.",
            "begin": "comenzar",
            "arrival": "me encontraste.",
            "notYet": "aun no.",
            "tryAgain": "intentar de nuevo",
            "eightMin": "(8 minutos)",
        ],
        "pt": [
            "ember": "eu estava te esperando.",
            "write1": "escreva por 8 minutos.",
            "write2": "nao pare por 8 segundos.",
            "write3": "chegue ao fim e eu acordo.",
            "begin": "comecar",
            "arrival": "voce me encontrou.",
            "notYet": "ainda nao.",
            "tryAgain": "tentar de novo",
            "eightMin": "(8 minutos)",
        ],
        "fr": [
            "ember": "je t'attendais.",
            "write1": "ecris pendant 8 minutes.",
            "write2": "ne t'arrete pas 8 secondes.",
            "write3": "arrive au bout et je me reveille.",
            "begin": "commencer",
            "arrival": "tu m'as trouve.",
            "notYet": "pas encore.",
            "tryAgain": "reessayer",
            "eightMin": "(8 minutes)",
        ],
        "de": [
            "ember": "ich habe auf dich gewartet.",
            "write1": "schreib 8 minuten lang.",
            "write2": "halt nicht 8 sekunden an.",
            "write3": "erreich das ende und ich erwache.",
            "begin": "beginnen",
            "arrival": "du hast mich gefunden.",
            "notYet": "noch nicht.",
            "tryAgain": "noch einmal",
            "eightMin": "(8 minuten)",
        ],
        "ja": [
            "ember": "ずっと待っていたよ。",
            "write1": "8分間、書いて。",
            "write2": "8秒以上止まらないで。",
            "write3": "最後まで書いたら、目が覚める。",
            "begin": "はじめる",
            "arrival": "見つけてくれたね。",
            "notYet": "まだだよ。",
            "tryAgain": "もう一度",
            "eightMin": "(8分)",
        ],
        "ko": [
            "ember": "기다리고 있었어.",
            "write1": "8분 동안 써.",
            "write2": "8초 이상 멈추지 마.",
            "write3": "끝까지 쓰면 내가 깨어나.",
            "begin": "시작",
            "arrival": "찾아줬구나.",
            "notYet": "아직이야.",
            "tryAgain": "다시 시도",
            "eightMin": "(8분)",
        ],
        "zh": [
            "ember": "我一直在等你。",
            "write1": "写满8分钟。",
            "write2": "不要停超过8秒。",
            "write3": "写到最后，我就会醒来。",
            "begin": "开始",
            "arrival": "你找到我了。",
            "notYet": "还没有。",
            "tryAgain": "再试一次",
            "eightMin": "(8分钟)",
        ],
        "ar": [
            "ember": "كنت انتظرك.",
            "write1": "اكتب لمدة 8 دقائق.",
            "write2": "لا تتوقف لمدة 8 ثوان.",
            "write3": "اصل الى النهاية واستيقظ.",
            "begin": "ابدا",
            "arrival": "وجدتني.",
            "notYet": "ليس بعد.",
            "tryAgain": "حاول مرة اخرى",
            "eightMin": "(8 دقائق)",
        ],
        "hi": [
            "ember": "मैं तुम्हारा इंतज़ार कर रहा था।",
            "write1": "8 मिनट लिखो।",
            "write2": "8 सेकंड से ज़्यादा मत रुको।",
            "write3": "अंत तक पहुँचो और मैं जागता हूँ।",
            "begin": "शुरू करो",
            "arrival": "तुमने मुझे ढूँढ लिया।",
            "notYet": "अभी नहीं।",
            "tryAgain": "फिर कोशिश करो",
            "eightMin": "(8 मिनट)",
        ],
        "it": [
            "ember": "ti stavo aspettando.",
            "write1": "scrivi per 8 minuti.",
            "write2": "non fermarti per 8 secondi.",
            "write3": "arriva alla fine e mi sveglio.",
            "begin": "iniziare",
            "arrival": "mi hai trovato.",
            "notYet": "non ancora.",
            "tryAgain": "riprova",
            "eightMin": "(8 minuti)",
        ],
        "nl": [
            "ember": "ik wachtte op je.",
            "write1": "schrijf 8 minuten.",
            "write2": "stop niet langer dan 8 seconden.",
            "write3": "bereik het einde en ik word wakker.",
            "begin": "begin",
            "arrival": "je hebt me gevonden.",
            "notYet": "nog niet.",
            "tryAgain": "opnieuw proberen",
            "eightMin": "(8 minuten)",
        ],
        "pl": [
            "ember": "czekalem na ciebie.",
            "write1": "pisz przez 8 minut.",
            "write2": "nie przerywaj na 8 sekund.",
            "write3": "dotrzej do konca, a sie obudze.",
            "begin": "zacznij",
            "arrival": "znalazles mnie.",
            "notYet": "jeszcze nie.",
            "tryAgain": "sprobuj ponownie",
            "eightMin": "(8 minut)",
        ],
        "tr": [
            "ember": "seni bekliyordum.",
            "write1": "8 dakika yaz.",
            "write2": "8 saniye durma.",
            "write3": "sonuna ulas ve uyanayim.",
            "begin": "basla",
            "arrival": "beni buldun.",
            "notYet": "henuz degil.",
            "tryAgain": "yeniden dene",
            "eightMin": "(8 dakika)",
        ],
        "ru": [
            "ember": "ya zhdal tebya.",
            "write1": "pishi 8 minut.",
            "write2": "ne ostanavlivaisya na 8 sekund.",
            "write3": "doidi do kontsa i ya prosnus.",
            "begin": "nachat",
            "arrival": "ty menya nashel.",
            "notYet": "yeshchyo net.",
            "tryAgain": "poprobovat snova",
            "eightMin": "(8 minut)",
        ],
        "id": [
            "ember": "aku menunggumu.",
            "write1": "tulis selama 8 menit.",
            "write2": "jangan berhenti 8 detik.",
            "write3": "sampai akhir dan aku terbangun.",
            "begin": "mulai",
            "arrival": "kamu menemukanku.",
            "notYet": "belum.",
            "tryAgain": "coba lagi",
            "eightMin": "(8 menit)",
        ],
    ]
}

// MARK: - Root Onboarding Ritual View

struct OnboardingRitualView: View {
    @EnvironmentObject private var appState: AppState
    @State private var phase: OnboardingPhase = .ember
    @State private var worldWarmth: Double = 0
    @State private var pendingReflection: MobileWriteResponse?

    private let copy = OnboardingCopy.current

    var body: some View {
        ZStack {
            // Persistent world background
            OnboardingWorldBackground(warmth: worldWarmth, kingdom: appState.kingdom)
                .ignoresSafeArea()

            switch phase {
            case .ember:
                EmberPhaseView(copy: copy) {
                    advanceTo(.invitation)
                }
            case .invitation:
                InvitationPhaseView(copy: copy) {
                    advanceTo(.writing)
                }
            case .writing:
                WritingPhaseView(
                    kingdom: appState.kingdom,
                    onWarmthChange: { worldWarmth = $0 },
                    onSessionEnd: handleSessionEnd
                )
                .environmentObject(appState)
            case .shortSessionEnd:
                ShortSessionPhaseView(copy: copy) {
                    advanceTo(.writing)
                }
            case .arrival:
                ArrivalPhaseView(copy: copy, kingdom: appState.kingdom) {
                    advanceTo(.unlock)
                }
            case .unlock:
                Color.clear
                    .onAppear { completeOnboarding() }
            }
        }
        .statusBarHidden(true)
        .animation(.easeInOut(duration: 0.8), value: phase)
    }

    private func advanceTo(_ next: OnboardingPhase) {
        withAnimation(.easeInOut(duration: 0.8)) {
            phase = next
        }
    }

    private func handleSessionEnd(capture: LocalWritingCapture?, wasRealAnky: Bool) {
        guard let capture else {
            advanceTo(.shortSessionEnd)
            return
        }

        if wasRealAnky {
            // Record and submit
            appState.setMirrorState(.mirrorDissolved)
            appState.recordFirstSession(timestamp: capture.finishedAt)
            appState.incrementCompletedSessions()
            Task {
                let model = WritingFlowModel(prompt: "")
                model.pendingCapture = capture
                await model.submitFinishedCapture(appState: appState)
            }
            worldWarmth = 1.0
            advanceTo(.arrival)
        } else {
            // Save the writing locally even if short
            appState.recordWriting(capture, response: nil, syncState: .localOnly)
            advanceTo(.shortSessionEnd)
        }
    }

    private func completeOnboarding() {
        Task {
            // Mark onboarding complete without requiring backup ceremony
            appState.hasCompletedWelcome = true
            UserDefaults.standard.set(true, forKey: "anky.has_completed_welcome")
            appState.setMirrorState(.firstMintComplete)
            appState.markUnlockedPublic()

            // Start background auth if not already authenticated
            if !appState.isAuthenticated {
                await appState.refreshAuthenticatedState(forceFreshSession: true)
            }

            appState.route = .unlocked
        }
    }
}

// MARK: - World Background (shared across all phases)

private struct OnboardingWorldBackground: View {
    let warmth: Double
    let kingdom: Kingdom

    var body: some View {
        ZStack {
            Color(hex: "0A0A12")

            // Warm radial that grows with session progress
            if warmth > 0.05 {
                RadialGradient(
                    colors: [
                        Color(hex: "1A150F").opacity(warmth * 0.6),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: UIScreen.main.bounds.height * 0.7
                )
                .animation(.easeInOut(duration: 2.0), value: warmth)
            }

            // Kingdom bloom at high warmth
            if warmth > 0.5 {
                VStack {
                    kingdom.color.opacity((warmth - 0.5) * 0.3)
                        .frame(height: 200)
                        .blur(radius: 80)
                    Spacer()
                }
                .animation(.easeInOut(duration: 3.0), value: warmth)
            }
        }
    }
}

// MARK: - Phase 1: Ember

private struct EmberPhaseView: View {
    let copy: OnboardingCopy
    let onAdvance: () -> Void
    @State private var emberOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var didAdvance = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            EmberView()
                .frame(width: 80, height: 80)
                .opacity(emberOpacity)

            Spacer().frame(height: 48)

            Text(copy.emberLine)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color(hex: "E8E4DC").opacity(textOpacity))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .onAppear {
            withAnimation(.easeIn(duration: 1.2)) {
                emberOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: 0.8)) {
                    textOpacity = 0.8
                }
            }
            // Auto-advance after ~2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                advance()
            }
        }
    }

    private func advance() {
        guard !didAdvance else { return }
        didAdvance = true
        onAdvance()
    }
}

// MARK: - Phase 2: Invitation (visual novel dialogue box)

private struct InvitationPhaseView: View {
    let copy: OnboardingCopy
    let onBegin: () -> Void
    @State private var line1Visible = false
    @State private var line2Visible = false
    @State private var line3Visible = false
    @State private var ctaVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Ember still present, slightly dimmer
            EmberView()
                .frame(width: 64, height: 64)
                .opacity(0.6)

            Spacer()

            // Dialogue box — visual novel style
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    if line1Visible {
                        Text(copy.writeLine1)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if line2Visible {
                        Text(copy.writeLine2)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if line3Visible {
                        Text(copy.writeLine3)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color(hex: "E8E4DC"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)

                if ctaVisible {
                    Button(action: onBegin) {
                        Text(copy.beginAction)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: "0A0A12"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color(hex: "E8E4DC"))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
        }
        .onAppear { revealSequence() }
    }

    private func revealSequence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 0.5)) { line1Visible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeIn(duration: 0.5)) { line2Visible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeIn(duration: 0.5)) { line3Visible = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            withAnimation(.easeIn(duration: 0.5)) { ctaVisible = true }
        }
    }
}

// MARK: - Phase 3: Writing

private struct WritingPhaseView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = WritingFlowModel(prompt: "")
    @StateObject private var keyboard = KeyboardObserver()
    let kingdom: Kingdom
    let onWarmthChange: (Double) -> Void
    let onSessionEnd: (LocalWritingCapture?, Bool) -> Void

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var warmthProgress: Double {
        min(Double(model.keystrokeDeltas.count) / 400.0, 1.0)
    }

    /// Checkpoint glow age (for "saved" indicator)
    private var checkpointAge: TimeInterval {
        let cadence: TimeInterval = 30
        guard model.sessionElapsed > 5 else { return -1 }
        return model.sessionElapsed.truncatingRemainder(dividingBy: cadence)
    }

    var body: some View {
        ZStack {
            // Particle system
            if model.phase == .writing || model.phase == .paused {
                OnboardingParticleView(
                    isActive: model.phase == .writing,
                    keystrokeCount: model.keystrokeDeltas.count,
                    kingdomColor: kingdom.color,
                    warmthProgress: warmthProgress
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Idle cooling overlay
            if model.idleElapsed > 5 {
                let coolingProgress = min((model.idleElapsed - 5) / 3.0, 1.0)
                Color(hex: "0A0A12")
                    .opacity(coolingProgress * 0.4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.5), value: coolingProgress)
            }

            if model.phase == .landing {
                Color.clear
                    .onAppear {
                        model.composerFocused = true
                        model.beginFocus()
                    }
            } else if model.phase == .writing || model.phase == .paused {
                writingActiveView
            } else if model.phase == .complete {
                Color.clear
                    .onAppear {
                        let capture = model.completedCapture
                        let isReal = capture?.qualifiesForAnky == true
                        onSessionEnd(capture, isReal)
                    }
            }

            // Hidden text input
            AnkyComposerTextView(
                text: $model.text,
                isFocused: $model.composerFocused,
                isVisuallyHidden: true,
                onUserInput: { model.handleInput($0) }
            )
            .frame(width: 1, height: 1)
            .opacity(0)
        }
        .onReceive(tick) { now in
            model.tick(at: now)
            onWarmthChange(warmthProgress)
        }
    }

    private var writingActiveView: some View {
        GeometryReader { geometry in
            let kbHeight = keyboard.height > 0
                ? keyboard.height - geometry.safeAreaInsets.bottom
                : 0

            VStack(spacing: 0) {
                // Top: 8-second idle drain bar
                IdleDrainBar(
                    idleElapsed: model.idleElapsed,
                    idleLimit: 8,
                    idleWarningStart: 3,
                    phase: .flow
                )

                // Center: text stream
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 120)
                            Text(model.text)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(Color(hex: "E8E4DC"))
                                .lineSpacing(10)
                                .padding(.horizontal, 28)
                                .padding(.bottom, 12)
                                .id("textBottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: model.text) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("textBottom", anchor: .bottom)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color(hex: "0A0A12").opacity(0.9), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.beginFocus() }

                // Bottom: checkpoint glow + countdown/countup timer
                WritingBottomBar(
                    sessionElapsed: model.sessionElapsed,
                    lastCheckpointAge: checkpointAge,
                    qualifiesForAnky: model.qualifiesForAnky,
                    onSend: { model.submitEarlyIfQualified() }
                )

                Color.clear
                    .frame(height: kbHeight)
                    .animation(.easeOut(duration: 0.25), value: kbHeight)
            }
        }
    }
}

// MARK: - Phase 3b: Short Session End

private struct ShortSessionPhaseView: View {
    let copy: OnboardingCopy
    let onRetry: () -> Void
    @State private var textVisible = false
    @State private var retryVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            EmberView()
                .frame(width: 60, height: 60)
                .opacity(0.3)

            Spacer().frame(height: 48)

            if textVisible {
                Text(copy.notYet)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color(hex: "E8E4DC").opacity(0.7))
                    .transition(.opacity)
            }

            Spacer().frame(height: 48)

            if retryVisible {
                VStack(spacing: 12) {
                    Button(action: onRetry) {
                        Text(copy.tryAgain)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: "E8E4DC"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color(hex: "E8E4DC").opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 60)

                    Text(copy.eightMinutes)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Color(hex: "E8E4DC").opacity(0.25))
                }
                .transition(.opacity)
            }

            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 0.6)) { textVisible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeIn(duration: 0.5)) { retryVisible = true }
            }
        }
    }
}

// MARK: - Phase 4: Arrival

private struct ArrivalPhaseView: View {
    let copy: OnboardingCopy
    let kingdom: Kingdom
    let onContinue: () -> Void
    @State private var emberScale: CGFloat = 0.8
    @State private var textVisible = false
    @State private var bloomVisible = false
    @State private var didContinue = false

    var body: some View {
        ZStack {
            // Kingdom color bloom
            if bloomVisible {
                RadialGradient(
                    colors: [kingdom.color.opacity(0.12), Color.clear],
                    center: .center,
                    startRadius: 50,
                    endRadius: 400
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }

            VStack(spacing: 0) {
                Spacer()

                // Larger, alive ember
                EmberView()
                    .frame(width: 120, height: 120)
                    .scaleEffect(emberScale)

                Spacer().frame(height: 48)

                if textVisible {
                    Text(copy.arrivalLine)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color(hex: "EF9F27"))
                        .transition(.opacity)
                }

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                emberScale = 1.0
                bloomVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.6)) { textVisible = true }
            }
            // Auto-advance after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                advance()
            }
        }
    }

    private func advance() {
        guard !didContinue else { return }
        didContinue = true
        onContinue()
    }
}
