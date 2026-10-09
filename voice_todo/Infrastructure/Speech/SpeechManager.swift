//
//  SpeechManager.swift
//  testVoiceInput
//
//  Created by A on 2026/9/25.
//

import Foundation
import Speech
import AVFoundation

// MARK: - Speech Manager

/// 用 SpeechAnalyzer／SpeechTranscriber（zh-TW），不用 SFSpeechRecognizer：後者每個 request 約限 1 分鐘，
/// SpeechAnalyzer 為長時間音訊設計，而且完全在裝置上辨識。
final class SpeechManager {

    private let locale: Locale

    private let audioEngine = AVAudioEngine()

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?

    private var converter: AVAudioConverter?

    private var inputBuilder:
        AsyncStream<AnalyzerInput>.Continuation?

    private var analyzerTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?

    /// 目前有效的 start；stop() 或新的 start() 會使舊的失效。
    private var session: UUID?


    init(locale: Locale) {
        self.locale = locale
    }


    func start(
        onResult: @escaping (AttributedString, Bool, CMTimeRange) -> Void
    ) async {

        let session = UUID()
        self.session = session

        do {

            // --------------------------------------------------
            // 1. Locale
            // --------------------------------------------------

            guard let locale =
                await SpeechTranscriber.supportedLocale(
                    equivalentTo: self.locale
                )
            else {
                print("[Speech] \(self.locale.identifier) is not supported.")
                return
            }


            // --------------------------------------------------
            // 2. Transcriber
            // --------------------------------------------------

            let transcriber = SpeechTranscriber(
                locale: locale,
                // 需要暫定結果判斷停頓（見 docs/specs/voice-input.md）
                preset: .timeIndexedProgressiveTranscription
            )

            self.transcriber = transcriber


            // --------------------------------------------------
            // 3. Speech assets
            // --------------------------------------------------

            if let request =
                try await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber]
                ) {

                print("[Speech] Installing speech assets...")

                try await request.downloadAndInstall()

                print("[Speech] Speech assets installed.")
            }


            // --------------------------------------------------
            // 4. Analyzer audio format
            // --------------------------------------------------

            guard let analyzerFormat =
                await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber]
                )
            else {
                print("[Speech] ERROR: No compatible audio format.")
                return
            }

#if os(iOS)
            // iOS 要先取得錄音權限並啟用錄音的 audio session，inputNode 才有正確的格式；macOS 不需要。
            // 來電、耳機插拔等中斷尚未處理（見 todo_list.md）。
            guard await AVAudioApplication.requestRecordPermission() else {
                print("[Speech] ERROR: No microphone permission.")
                return
            }
            // 語音報告要同時播放：從喇叭播放，藍牙耳機也能聽（見 docs/specs/spoken-report.md）。
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
#endif

            // 以下皆為同步步驟；若 await 期間已被 stop() 或
            // 新的 start() 取代，就放棄，避免重複 installTap。
            guard self.session == session else {
                print("[Speech] Start superseded.")
                return
            }

            print(
                "[Speech] Analyzer format: " +
                "\(analyzerFormat.sampleRate) Hz, " +
                "\(analyzerFormat.channelCount) channel(s)"
            )


            // --------------------------------------------------
            // 5. Analyzer
            // --------------------------------------------------

            let analyzer = SpeechAnalyzer(
                modules: [transcriber]
            )

            self.analyzer = analyzer


            // --------------------------------------------------
            // 6. Input stream
            // --------------------------------------------------

            let (inputStream, inputBuilder) =
                AsyncStream.makeStream(
                    of: AnalyzerInput.self
                )

            self.inputBuilder = inputBuilder


            // --------------------------------------------------
            // 7. Receive transcription results
            // --------------------------------------------------

            resultTask = Task {

                do {

                    print("[Speech] Result stream started.")

                    for try await result
                        in transcriber.results {

                        await MainActor.run {
                            onResult(
                                result.text,
                                result.isFinal,
                                result.range
                            )
                        }
                    }

                    print("[Speech] Result stream ended.")

                } catch {

                    printSpeechError(
                        "[Speech] Result stream error",
                        error
                    )
                }
            }


            // --------------------------------------------------
            // 8. Start analyzer
            // --------------------------------------------------

            analyzerTask = Task {

                do {

                    print("[Speech] Starting analyzer...")

                    try await analyzer.start(
                        inputSequence: inputStream
                    )

                    // IMPORTANT:
                    // This should remain running while the
                    // input stream is alive.
                    print("[Speech] Analyzer started.")

                } catch {

                    printSpeechError(
                        "[Speech] Analyzer error",
                        error
                    )
                }
            }


            // --------------------------------------------------
            // 9. Microphone
            // --------------------------------------------------

            let inputNode = audioEngine.inputNode

            // 回音消除：語音報告念的時候繼續聆聽，不要聽到小精靈自己（見 docs/specs/spoken-report.md）。
            // 打開後麥克風的格式可能改變，所以要在讀取格式之前打開；失敗時照常聆聽，只是沒有回音消除。
            // 預設會把其他聲音（包括 TTS）壓得很小，所以降到最低。
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
            } catch {
                printSpeechError("[Speech] Voice processing unavailable", error)
            }

            let microphoneFormat =
                inputNode.inputFormat(
                    forBus: 0
                )

            print(
                "[Speech] Microphone format: " +
                "\(microphoneFormat.sampleRate) Hz, " +
                "\(microphoneFormat.channelCount) channel(s)"
            )


            // --------------------------------------------------
            // 10. Audio converter
            // --------------------------------------------------

            guard let converter =
                AVAudioConverter(
                    from: microphoneFormat,
                    to: analyzerFormat
                )
            else {
                print(
                    "[Speech] ERROR: " +
                    "Cannot create AVAudioConverter."
                )
                return
            }

            // macOS 打開回音消除後麥克風是多聲道（實測 5 聲道、沒有喇叭配置），預設的混成單聲道會輸出靜音；
            // 回音消除後的人聲在第 0 聲道，只取它。
            if microphoneFormat.channelCount > 1 {
                converter.channelMap = [0]
            }

            self.converter = converter


            // --------------------------------------------------
            // 11. Microphone tap
            // --------------------------------------------------

            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: microphoneFormat
            ) {
                [weak self] buffer, time in

                guard let self else {
                    return
                }

                self.processAudio(
                    buffer: buffer,
                    time: time,
                    converter: converter,
                    outputFormat: analyzerFormat,
                    inputBuilder: inputBuilder
                )
            }


            // --------------------------------------------------
            // 12. Start audio engine
            // --------------------------------------------------

            audioEngine.prepare()

            try audioEngine.start()

            print("[Speech] Audio engine started.")
            print("[Speech] Listening continuously...")

        } catch {

            printSpeechError(
                "[Speech] Failed to start speech recognition",
                error
            )
        }
    }


    private func processAudio(
        buffer: AVAudioPCMBuffer,
        time: AVAudioTime,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        inputBuilder:
            AsyncStream<AnalyzerInput>.Continuation
    ) {

        let ratio =
            outputFormat.sampleRate /
            buffer.format.sampleRate

        let outputFrameCount =
            AVAudioFrameCount(
                ceil(
                    Double(buffer.frameLength) * ratio
                )
            )

        guard let outputBuffer =
            AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCount
            )
        else {
            print(
                "[Speech] ERROR: " +
                "Cannot allocate converted audio buffer."
            )
            return
        }


        var conversionError: NSError?

        var suppliedInput = false

        let status =
            converter.convert(
                to: outputBuffer,
                error: &conversionError
            ) { _, status in

                if suppliedInput {
                    status.pointee = .noDataNow
                    return nil
                }

                suppliedInput = true
                status.pointee = .haveData

                return buffer
            }


        if let conversionError {

            printSpeechError(
                "[Speech] Audio conversion error",
                conversionError
            )

            return
        }


        switch status {

        case .haveData:
            break

        case .inputRanDry:
//            print(
//                "[Speech] WARNING: " +
//                "Audio converter input ran dry."
//            )
            break

        case .endOfStream:
            print(
                "[Speech] WARNING: " +
                "Audio converter reached end of stream."
            )

        @unknown default:
            print(
                "[Speech] WARNING: " +
                "Unknown converter status."
            )
        }


        guard outputBuffer.frameLength > 0 else {
            print(
                "[Speech] WARNING: " +
                "Converted buffer contains no audio frames."
            )
            return
        }


        // Preserve the original microphone time.
        let startTime =
            CMTime(
                value: time.sampleTime,
                timescale: CMTimeScale(
                    time.sampleRate
                )
            )

        let input =
            AnalyzerInput(
                buffer: outputBuffer,
                bufferStartTime: startTime
            )

        inputBuilder.yield(input)
    }


    /// 把 time 之前的音訊定稿；time 為 nil 時定稿到目前為止的所有音訊。
    func finalize(through time: CMTime?) async {
        guard let analyzer else {
            return
        }
        do {
            try await analyzer.finalize(through: time)
        } catch {
            printSpeechError("[Speech] Finalize error", error)
        }
    }


    func stop() {

        print("[Speech] Stopping...")

        session = nil

        audioEngine.stop()

        audioEngine.inputNode.removeTap(
            onBus: 0
        )

#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif

        inputBuilder?.finish()

        analyzerTask?.cancel()
        resultTask?.cancel()

        analyzerTask = nil
        resultTask = nil

        inputBuilder = nil
        converter = nil
        analyzer = nil
        transcriber = nil

        print("[Speech] Stopped.")
    }
}


// MARK: - Error Logging

private func printSpeechError(
    _ prefix: String,
    _ error: Error
) {

    let nsError = error as NSError

    print("""
    ==================================================
    \(prefix)
    --------------------------------------------------
    Type:
    \(type(of: error))

    Description:
    \(error.localizedDescription)

    Domain:
    \(nsError.domain)

    Code:
    \(nsError.code)

    UserInfo:
    \(nsError.userInfo)

    Full Error:
    \(error)

    ==================================================
    """)
}

// MARK: - SpeechInput

extension SpeechManager: SpeechInput {

    func start(onResult: @escaping (String, Bool) -> Void) async {
        await start { text, isFinal, _ in
            onResult(String(text.characters), isFinal)
        }
    }

    func finalize() async {
        await finalize(through: nil)
    }
}
