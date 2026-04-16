//
//  MirrorView.swift
//  Anky
//
//  The mirror onboarding — camera feed, seed phrase reveal, writing through.
//  This screen appears exactly once per user, ever.
//

import AVFoundation
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - Camera Feed

class CameraFeedManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: CGImage?
    private let captureSession = AVCaptureSession()
    private let context = CIContext()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "anky.camera.processing", qos: .userInteractive)
    private var isRunning = false

    /// Ripple phase — continuously animated
    var ripplePhase: Double = 0
    /// Desaturation amount (0 = full color, 1 = grayscale)
    var desaturation: Double = 0.4

    func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                DispatchQueue.main.async {
                    self.setupSession()
                }
            }
        }
    }

    private func setupSession() {
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Mirror the front camera (actual mirror behavior)
        if let connection = videoOutput.connection(with: .video) {
            connection.isVideoMirrored = false // front camera is already mirrored by default; false = true mirror
        }

        startRunning()
    }

    func startRunning() {
        guard !isRunning else { return }
        isRunning = true
        processingQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func stopRunning() {
        guard isRunning else { return }
        isRunning = false
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 1. Desaturation
        let saturationFilter = CIFilter.colorControls()
        saturationFilter.inputImage = ciImage
        saturationFilter.saturation = Float(1.0 - desaturation)
        saturationFilter.brightness = -0.05
        saturationFilter.contrast = 1.05
        if let output = saturationFilter.outputImage {
            ciImage = output
        }

        // 2. Ripple distortion — gentle sine wave displacement
        let bumpFilter = CIFilter.bumpDistortion()
        let imageExtent = ciImage.extent
        let centerX = imageExtent.midX + CGFloat(sin(ripplePhase * 0.7)) * 80
        let centerY = imageExtent.midY + CGFloat(cos(ripplePhase * 0.5)) * 60
        bumpFilter.inputImage = ciImage
        bumpFilter.center = CGPoint(x: centerX, y: centerY)
        bumpFilter.radius = 400
        bumpFilter.scale = Float(sin(ripplePhase) * 0.015)
        if let output = bumpFilter.outputImage {
            ciImage = output
        }

        // 3. Vignette
        let vignetteFilter = CIFilter.vignette()
        vignetteFilter.inputImage = ciImage
        vignetteFilter.intensity = 1.8
        vignetteFilter.radius = 1.2
        if let output = vignetteFilter.outputImage {
            ciImage = output
        }

        // Render to CGImage
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            DispatchQueue.main.async { [weak self] in
                self?.currentFrame = cgImage
            }
        }
    }
}

// MARK: - Mirror View (States 0 → 1 → 2)

struct MirrorView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var camera = CameraFeedManager()
    @State private var rippleTimer: Timer?
    @State private var mirrorPhase: MirrorPhase = .reflection

    enum MirrorPhase {
        case reflection       // Just the user's face (2-second pause)
        case seedRevealing    // Words fading in one by one
        case seedShown        // All words + buttons visible
        case seedSinking      // Words sinking into mirror
        case waitingToWrite   // Empty mirror + "write for 8 minutes"
        case writing          // Writing through the mirror
    }

    // Seed phrase words (from AppState)
    private var seedWords: [String] {
        (appState.pendingMnemonic ?? "").split(separator: " ").map(String.init)
    }

    @State private var revealedWordCount = 0
    @State private var buttonsVisible = false
    @State private var writePromptVisible = false
    @State private var sinkingWords = false

    // Writing state
    @State private var showWritingSession = false

    var body: some View {
        ZStack {
            // Camera feed background
            cameraBackground

            // Content based on phase
            switch mirrorPhase {
            case .reflection:
                Color.clear
                    .onAppear { beginReflectionPause() }

            case .seedRevealing, .seedShown:
                seedPhraseOverlay

            case .seedSinking:
                sinkingSeedOverlay

            case .waitingToWrite:
                writePrompt

            case .writing:
                Color.clear
            }
        }
        .ignoresSafeArea()
        .onAppear {
            camera.requestAccess()
            startRippleAnimation()

            // Determine initial phase from mirror state
            switch appState.mirrorState {
            case .virgin:
                mirrorPhase = .reflection
            case .seedRevealed:
                mirrorPhase = .seedShown
                revealedWordCount = seedWords.count
                buttonsVisible = true
            case .seedConfirmed:
                mirrorPhase = .waitingToWrite
                writePromptVisible = true
            default:
                break
            }
        }
        .onDisappear {
            rippleTimer?.invalidate()
            camera.stopRunning()
        }
        .fullScreenCover(isPresented: $showWritingSession) {
            MirrorWritingView()
                .environmentObject(appState)
        }
    }

    // MARK: - Camera Background

    private var cameraBackground: some View {
        GeometryReader { geo in
            if let frame = camera.currentFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                // Fallback while camera loads
                Color.black
            }
        }
    }

    // MARK: - Seed Phrase Overlay

    private var seedPhraseOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            // 3×4 grid of seed words
            VStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 20) {
                        ForEach(0..<3, id: \.self) { col in
                            let index = row * 3 + col
                            if index < seedWords.count {
                                seedWordView(index: index, word: seedWords[index])
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer().frame(height: 60)

            // Confirmation buttons
            if buttonsVisible {
                VStack(spacing: 12) {
                    Button {
                        confirmSeedWrittenDown()
                    } label: {
                        Text("I've written these down")
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        confirmSeedKeychain()
                    } label: {
                        Text("Save to Keychain")
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .transition(.opacity.animation(.easeIn(duration: 0.5)))
            }

            Spacer()
        }
    }

    private func seedWordView(index: Int, word: String) -> some View {
        Text(word)
            .font(.system(size: 17, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.9))
            .shadow(color: .white.opacity(0.3), radius: 8, x: 0, y: 0)
            .frame(width: 90)
            .opacity(index < revealedWordCount ? 1 : 0)
            .animation(.easeIn(duration: 0.3).delay(Double(index) * 0.2), value: revealedWordCount)
    }

    // MARK: - Sinking Seed Overlay

    private var sinkingSeedOverlay: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 20) {
                        ForEach(0..<3, id: \.self) { col in
                            let index = row * 3 + col
                            if index < seedWords.count {
                                Text(seedWords[index])
                                    .font(.system(size: 17, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Color.white)
                                    .opacity(sinkingWords ? 0 : 0.9)
                                    .offset(y: sinkingWords ? 100 + Double(index) * 15 : 0)
                                    .animation(
                                        .easeIn(duration: 0.8).delay(Double(index) * 0.08),
                                        value: sinkingWords
                                    )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Write Prompt

    private var writePrompt: some View {
        VStack {
            Spacer()

            Text("write for 8 minutes to pass through")
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(Color.white.opacity(writePromptVisible ? 0.7 : 0))
                .animation(.easeIn(duration: 1.0), value: writePromptVisible)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.setMirrorState(.firstSessionInProgress)
            showWritingSession = true
        }
    }

    // MARK: - Actions

    private func beginReflectionPause() {
        // 2-second pause, then reveal seed words
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            mirrorPhase = .seedRevealing
            appState.setMirrorState(.seedRevealed)
            revealSeedWords()
        }
    }

    private func revealSeedWords() {
        // Reveal all 12 words with staggered animation + haptic per word
        revealedWordCount = seedWords.count
        let lightImpact = UIImpactFeedbackGenerator(style: .light)
        for i in 0..<seedWords.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                lightImpact.impactOccurred(intensity: 0.4)
            }
        }

        // After all words revealed (~4 seconds), show buttons
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seedWords.count) * 0.2 + 0.5) {
            withAnimation {
                buttonsVisible = true
                mirrorPhase = .seedShown
            }
        }
    }

    private func confirmSeedWrittenDown() {
        transitionToWriteState()
    }

    private func confirmSeedKeychain() {
        transitionToWriteState()
    }

    private func transitionToWriteState() {
        // Sink the words into the mirror
        mirrorPhase = .seedSinking
        withAnimation {
            buttonsVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sinkingWords = true
        }

        // After sinking animation, show write prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Task {
                await appState.completeWelcome()
                appState.setMirrorState(.seedConfirmed)
                appState.deriveKingdom()
            }

            mirrorPhase = .waitingToWrite

            // Fade in the prompt after a brief pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                writePromptVisible = true
            }
        }
    }

    // MARK: - Ripple Animation

    private func startRippleAnimation() {
        rippleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            camera.ripplePhase += 0.03
        }
    }
}

// MARK: - Mirror Writing View (State 3)

struct MirrorWritingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraFeedManager()
    @StateObject private var model = WritingFlowModel(prompt: "")
    @StateObject private var keyboard = KeyboardObserver()
    @State private var rippleTimer: Timer?
    @State private var showDissolve = false

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    /// Camera opacity fades as user writes — gone by ~4 minutes
    private var cameraOpacity: Double {
        guard model.hasStarted else { return 1.0 }
        let progress = min(model.sessionElapsed / 240.0, 1.0) // 4 minutes to fully fade
        return max(1.0 - progress, 0)
    }

    /// During idle (seconds 5-8), camera reasserts
    private var idleReassertionOpacity: Double {
        guard model.phase == .writing else { return 0 }
        guard model.idleElapsed >= 5 else { return 0 }
        let progress = min((model.idleElapsed - 5) / 3.0, 1.0)
        return progress * 0.6
    }

    /// Subtle progress — vignette recedes as time passes
    private var vignetteRecession: Double {
        min(model.sessionElapsed / AnkyContract.Qualification.minimumDurationSeconds, 1.0)
    }

    var body: some View {
        ZStack {
            // Black base
            Color.black.ignoresSafeArea()

            // Camera feed — fades as user writes
            GeometryReader { geo in
                if let frame = camera.currentFrame {
                    Image(decorative: frame, scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(max(cameraOpacity + idleReassertionOpacity, 0))
                }
            }
            .ignoresSafeArea()

            // Writing area
            if model.phase == .landing {
                mirrorWritingLanding
            } else {
                mirrorWritingActive
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
        .statusBarHidden(true)
        .onReceive(tick) { now in model.tick(at: now) }
        .onAppear {
            camera.requestAccess()
            startRippleAnimation()
            model.updatePrompt(appState.prompt)
        }
        .onDisappear {
            rippleTimer?.invalidate()
            camera.stopRunning()
        }
        .onChange(of: model.phase) { newPhase in
            if newPhase == .complete {
                handleSessionComplete()
            }
        }
        .fullScreenCover(isPresented: $showDissolve) {
            if let capture = model.completedCapture {
                MirrorDissolveView(capture: capture, sessionText: model.text)
                    .environmentObject(appState)
            }
        }
    }

    private var mirrorWritingLanding: some View {
        VStack {
            Spacer()
            Text("tap to begin")
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(Color.white.opacity(0.5))
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.beginFocus()
        }
    }

    private var mirrorWritingActive: some View {
        GeometryReader { geometry in
            let kbHeight = keyboard.height > 0
                ? keyboard.height - geometry.safeAreaInsets.bottom
                : 0

            VStack(spacing: 0) {
                // Text stream
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 200)

                            Text(model.text)
                                .font(.system(size: 16, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .lineSpacing(12)
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
                // Dark gradient at top for readability
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.9), Color.black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .allowsHitTesting(false)
                }
                .background(Color.black.opacity(0.4))
                .contentShape(Rectangle())
                .onTapGesture {
                    model.beginFocus()
                }

                // Keyboard spacer
                Color.clear
                    .frame(height: kbHeight)
                    .animation(.easeOut(duration: 0.25), value: kbHeight)
            }
        }
    }

    private func handleSessionComplete() {
        guard let capture = model.completedCapture else {
            // Failed session — return to mirror state 2
            appState.setMirrorState(.seedConfirmed)
            dismiss()
            return
        }

        if capture.qualifiesForAnky {
            // Success — show dissolve
            appState.setMirrorState(.mirrorDissolved)
            appState.recordFirstSession(timestamp: capture.finishedAt)
            appState.incrementCompletedSessions()

            // Submit to backend
            Task {
                model.pendingCapture = capture
                await model.submitFinishedCapture(appState: appState)
            }

            showDissolve = true
        } else {
            // Didn't reach 8 minutes — go back to state 2
            appState.setMirrorState(.seedConfirmed)
            dismiss()
        }
    }

    private func startRippleAnimation() {
        rippleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            camera.ripplePhase += 0.03
        }
    }
}
