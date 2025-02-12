//
//  CatPurr.swift
//  aiTest
//
//  Created by Peter Rogers on 10/02/2025.
//

import AudioKit
import SoundpipeAudioKit
import Vision

import Foundation

class CatPurrSynth: ObservableObject  {
	let engine = AudioEngine()

	// Noise source
	let noise = PinkNoise()

	// Tremolo node for amplitude modulation
	let tremolo: Tremolo

	// Filter to shape the noise
	let filter: MoogLadder
	let mixer: Mixer
	let subOsc:Oscillator
	let mixMain:Mixer

	// A timer to update our “slow LFO” that modulates tremolo frequency
	private var lfoTimer: Timer?
	// Track the total time so we can feed it into the sine wave
	private var totalTime: Double = 0
	private var waitTime = 2.0

	init() {
		// Initialize the tremolo with some default frequency & depth
		
		tremolo = Tremolo(noise,
						  frequency: 30.0,
						  depth: 0.9)

		// Filter the output to soften the noise
		filter = MoogLadder(tremolo,
							cutoffFrequency: 150,
							resonance: 0.8)
		//subOsc = Oscillator(waveform: <#T##Table#>)
		subOsc = Oscillator(waveform: Table(.sine), frequency: 15, amplitude: 1.0)
		mixer = Mixer(filter)
		mixMain = Mixer(mixer, subOsc)
		let shelf = LowShelfFilter(mixMain,
								   cutoffFrequency: 120, // frequencies below 120Hz
								   gain: 6.0) // +6dB boost

		engine.output = shelf
		do {
			try engine.start()
			noise.start()
			tremolo.start()
		} catch {
			print("AudioKit engine failed to start: \(error)")
		}

		// Begin our LFO-based modulation
		startLFO()
	}

	deinit {
		stopLFO()
		engine.stop()
	}
	
	func updateFromFaceAngles(faceObs:[VNFaceObservation]) {
		if let firstFace = faceObs.first {
			if(mixMain.volume == 0){
				mixMain.volume = 0.05
			}
			if(mixMain.volume < 1){
				mixMain.volume = mixMain.volume * 1.15
			}
			
			//	print(firstFace)
			let pitchVal = firstFace.pitch?.floatValue ?? 0
			let yawVal   = firstFace.yaw?.floatValue ?? 0
			let rollVal  = firstFace.roll?.floatValue ?? 0
			//print("pitch: \(pitchVal)
			let res = faceCenterScore(pitch: Double(pitchVal), yaw: Double(yawVal), roll: Double(rollVal))
			let newX = 130 + (300 - 130) * res
			filter.cutoffFrequency = Float(newX)
			//let delay  = 2 + (6 - 2) * res
			
		}
		
	}
	
	func noFaceFound(){
		mixMain.volume -= mixMain.volume * 0.05
		if(mixMain.volume <= 0.0){
			mixMain.volume = 0.0
		}
	}
	
	
	func faceCenterScore(pitch: Double, yaw: Double, roll: Double) -> Double {
		// 0.3 rad ≈ 17 degrees. Adjust to taste.
		let threshold: Double = 0.4

		   // If *any* angle is beyond ±0.2, we consider that "looking away"
		   if abs(pitch) > threshold
			   || abs(yaw) > threshold
			   || abs(roll) > threshold {
			  // let v = player?.volume ?? 0
			  // return Double(v*0.01)
			   return 0.0
			   // e.g., set the rate high (2.0), or even mute volume, or whatever:
			  
			  // print("Looking away — setting rate to 2.0")

		   }
		
		
		let maxAngle = 0.3
		

		let pitchScore = max(0, 1 - abs(pitch) / maxAngle)
		let yawScore   = max(0, 1 - abs(yaw)   / maxAngle)
		let rollScore  = max(0, 1 - abs(roll)  / maxAngle)

		// Average the three scores to get a combined "facing forward" measure
		let combinedScore = (pitchScore + yawScore + rollScore) / 3.0
		return combinedScore
	}

	/// Sets up a timer to run ~30 times/sec, updating tremolo frequency.
	private func startLFO() {
		let updateInterval = 1.0 / 30.0  // 30 Hz updates
		lfoTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
			guard let self = self else { return }
			self.updateTremoloLFO(dt: updateInterval)
		}
	}

	private func stopLFO() {
		lfoTimer?.invalidate()
		lfoTimer = nil
	}

	/// Called every frame to increment time and compute a new frequency.
	private func updateTremoloLFO(dt: Double) {
		totalTime += dt

		// Let's define a 4-second cycle for a slow up/down.
		// fraction goes from 0 -> 1 every 4 seconds
		let period = 2.0
		let fraction = (totalTime.truncatingRemainder(dividingBy: period)) / period

		// We'll generate a sine wave from -1..+1, then scale it to 0..1,
		// and then map that to 22..28 Hz.
		//  - sin(2 * π * fraction) goes -1..+1
		let sineValue = sin(2.0 * .pi * fraction)         // range -1..+1
		let normalized = 0.5 + 0.5 * sineValue            // now 0..1
		let minFreq: Float = 400
		let maxFreq: Float = 2000
		let newFreq = minFreq + (maxFreq - minFreq) * Float(normalized)
		let minFreqq: Float = 20
		let maxFreqq: Float = 70
		let newFreqq = minFreqq + (maxFreqq - minFreqq) * Float(normalized)

		// Update tremolo frequency
		tremolo.frequency = AUValue(newFreqq)
		filter.resonance = AUValue(normalized/1.6)
		tremolo.depth = AUValue(newFreq)
		mixer.volume = AUValue(normalized)+0.1
	}

	func stop() {
		stopLFO()
		noise.stop()
		tremolo.stop()
		engine.stop()
	}
}
