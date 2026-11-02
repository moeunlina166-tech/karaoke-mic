import AVFoundation
import Flutter
import UIKit

/// Live mic -> gain -> reverb -> echo -> output (low latency, runs in background)
final class KaraokeEngine {
    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 1)   // used only for global gain
    private let reverb = AVAudioUnitReverb()
    private let delay = AVAudioUnitDelay()
    private var graphBuilt = false

    private(set) var level: Float = 0
    private(set) var isRunning = false

    var routeName: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? ""
    }

    init() {
        eq.bands[0].bypass = true
        eq.globalGain = 0
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 30
        delay.wetDryMix = 25
        delay.delayTime = 0.25
        delay.feedback = 30
        delay.lowPassCutoff = 6000

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            try? self.engine.start()
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self, self.isRunning,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw),
                  type == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            try? self.engine.start()
        }
    }

    // MARK: controls
    func setMicGain(_ db: Float) { eq.globalGain = db }
    func setEcho(_ mix: Float) { delay.wetDryMix = mix }
    func setEchoTime(_ seconds: Double) { delay.delayTime = seconds }
    func setReverb(_ mix: Float) { reverb.wetDryMix = mix }
    func setMuted(_ muted: Bool) { engine.mainMixerNode.outputVolume = muted ? 0 : 1 }

    func start(_ done: @escaping (String?) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    done("សូមអនុញ្ញាតមីក្នុង Settings > Karaoke Mic > Microphone")
                    return
                }
                do {
                    let s = AVAudioSession.sharedInstance()
                    try s.setCategory(.playAndRecord, mode: .default,
                                      options: [.allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
                    try s.setPreferredIOBufferDuration(0.005)
                    try s.setActive(true)
                    try self.buildGraphIfNeeded()
                    try self.engine.start()
                    self.isRunning = true
                    done(nil)
                } catch {
                    done(error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        level = 0
    }

    private func buildGraphIfNeeded() throws {
        guard !graphBuilt else { return }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "Karaoke", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "រកមិនឃើញមីក្រូហ្វូន"])
        }
        engine.attach(eq)
        engine.attach(reverb)
        engine.attach(delay)
        engine.connect(engine.inputNode, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: delay, format: format)
        engine.connect(delay, to: engine.mainMixerNode, format: format)

        eq.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += data[i] * data[i] }
            let rms = n > 0 ? sqrt(sum / Float(n)) : 0
            self?.level = min(1, rms * 4)
        }
        engine.prepare()
        graphBuilt = true
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private let karaoke = KaraokeEngine()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        let channel = FlutterMethodChannel(
            name: "karaoke/engine",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let k = self?.karaoke else { return }
            let d = (call.arguments as? Double) ?? 0
            switch call.method {
            case "start":
                k.start { err in
                    if let err = err {
                        result(FlutterError(code: "START_FAILED", message: err, details: nil))
                    } else {
                        result(nil)
                    }
                }
            case "stop":        k.stop(); result(nil)
            case "setMicGain":  k.setMicGain(Float(d)); result(nil)
            case "setEcho":     k.setEcho(Float(d)); result(nil)
            case "setEchoTime": k.setEchoTime(d); result(nil)
            case "setReverb":   k.setReverb(Float(d)); result(nil)
            case "setMute":     k.setMuted((call.arguments as? Bool) ?? false); result(nil)
            case "getLevel":    result(Double(k.level))
            case "getRoute":    result(k.routeName)
            default:            result(FlutterMethodNotImplemented)
            }
        }
    }
}
