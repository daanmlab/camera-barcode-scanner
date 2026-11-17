import AVFoundation
import Foundation

/// A short, high scan beep, like a handheld barcode scanner.
/// The tone is made once at startup. Each play only schedules the buffer, so it never waits on audio.
@MainActor
final class Beeper {
  static let frequency = 2_800.0
  static let duration = 0.1
  static let ramp = 0.005
  static let volume: Float = 0.4

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let buffer: AVAudioPCMBuffer?
  private var endsAt = Date.distantPast

  init() {
    let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    let rate = outputRate > 0 ? outputRate : 48_000
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
      buffer = nil
      return
    }
    buffer = Beeper.makeTone(format: format)
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.prepare()
    // Start the player now. Its first start takes a few milliseconds, and a scan must not wait.
    try? engine.start()
    player.play()
  }

  /// Plays the beep. A new beep cuts off the one before it.
  func play() {
    guard let buffer else { return }
    // The engine stops when the output device changes. Start it again on demand.
    if !engine.isRunning {
      do { try engine.start() } catch { return }
    }
    player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    if !player.isPlaying { player.play() }
    endsAt = Date().addingTimeInterval(Beeper.duration)
  }

  /// Waits until the last beep ends, so the process does not exit in the middle of it.
  func waitUntilDone() {
    let remaining = endsAt.timeIntervalSinceNow
    if remaining > 0 { Thread.sleep(forTimeInterval: min(remaining + 0.02, 0.2)) }
    engine.stop()
  }

  /// A sine tone with a raised-cosine fade in and out, so it starts and ends without a click.
  private static func makeTone(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let rate = format.sampleRate
    let frames = AVAudioFrameCount(rate * duration)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
      let samples = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = frames
    let rampFrames = Int(rate * ramp)
    let count = Int(frames)
    for i in 0..<count {
      let edge = min(i, count - 1 - i)
      let gain = edge < rampFrames ? 0.5 - 0.5 * cos(Double.pi * Double(edge) / Double(rampFrames)) : 1
      samples[i] = Float(sin(2 * Double.pi * frequency * Double(i) / rate) * gain) * volume
    }
    return buffer
  }
}
