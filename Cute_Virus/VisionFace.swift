//
//  VisionFace.swift
//  aiTest
//
//  Created by Peter Rogers on 07/02/2025.
//

import SwiftUI
import AVFoundation
@preconcurrency import Vision

struct VisionFace: View {
	
	/// You can expose this as a binding if you want to pass it back to a parent view
	@State private var faceObservation: VNFaceObservation?
//	@ObservedObject var viewModel: ViewModel
//	@StateObject var audioViewModel = AudioManipulation()
	@StateObject var catPurr = CatPurrSynth()

	var body: some View {
		ZStack {
			// The live camera feed
			CameraPreview(faceObservation: $faceObservation, catPurr: catPurr)
				.edgesIgnoringSafeArea(.all)
				.opacity(0.5)
				
//				.onAppear {
//					audioViewModel.loadWavFile(named: "Bass-Drum-3")
//					}
//				

			// Overlay: If you want to display the face bounding box, you can add a rectangle
			if let face = faceObservation {
				GeometryReader { geometry in
					let frameSize = geometry.size
					FaceBoundingView(faceObservation: face, frameSize: frameSize)
						.fill(.blue)
						.stroke(Color.red, lineWidth: 2)
						.opacity(0.1)
				}
			}
		}
	}
}

struct CameraPreview: UIViewRepresentable {
	@Binding var faceObservation: VNFaceObservation?
	//@ObservedObject var audioKitViewModel: AudioManipulation
	@ObservedObject var catPurr: CatPurrSynth
	func makeUIView(context: Context) -> CameraPreviewView {
		let view = CameraPreviewView()
		view.delegate = context.coordinator

		// Give your coordinator a reference to the `CameraPreviewView`
		context.coordinator.cameraPreviewView = view

		// Now that the coordinator knows the real view, set up the capture session
		context.coordinator.configureCaptureSession()

		return view
	}

	func updateUIView(_ uiView: CameraPreviewView, context: Context) {
		// Nothing to update here
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(self, catPurr: catPurr)
	}

	class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
		private let parent: CameraPreview
		private let sequenceHandler = VNSequenceRequestHandler()

		// Keep a weak or strong reference to the preview view
		// (strong is typically fine, since SwiftUI will manage its lifecycle).
		var cameraPreviewView: CameraPreviewView?
		let catPurr: CatPurrSynth?

		init(_ parent: CameraPreview, catPurr: CatPurrSynth) {
			self.parent = parent
			self.catPurr = catPurr
			super.init()
		}

		func configureCaptureSession() {
			guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
													   for: .video,
													   position: .front) else {
				print("Error: Unable to access front camera.")
				return
			}

			let session = AVCaptureSession()
			session.sessionPreset = .high

			do {
				let input = try AVCaptureDeviceInput(device: device)
				if session.canAddInput(input) {
					session.addInput(input)
				}
			} catch {
				print("Error: Cannot create camera input - \(error)")
				return
			}

			let output = AVCaptureVideoDataOutput()
			output.videoSettings = [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
			]
			let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInitiated)
			output.setSampleBufferDelegate(self, queue: videoQueue)
			if session.canAddOutput(output) {
				session.addOutput(output)
			}

			// Adjust orientation if needed
			if let connection = output.connection(with: .video) {
				//fix this warning
				connection.videoRotationAngle = 90
			}

			// Assign the session to the actual preview layer
			cameraPreviewView?.previewLayer.session = session

			// Start running the session
			DispatchQueue.global(qos: .userInitiated).async {
				session.startRunning()
			}
		}

		// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
		func captureOutput(_ output: AVCaptureOutput,
						   didOutput sampleBuffer: CMSampleBuffer,
						   from connection: AVCaptureConnection) {
			guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

			let detectFaceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
				guard let self = self else { return }
				guard error == nil else {
					print("Face detection error: \(String(describing: error))")
					return
				}

				if let results = request.results as? [VNFaceObservation],
				   let firstFace = results.first {
					DispatchQueue.main.async {

						self.parent.faceObservation = firstFace
						self.catPurr?.updateFromFaceAngles(
							faceObs:results
							)
						
					}
				} else {
					DispatchQueue.main.async {
						print("no face")
						self.catPurr?.noFaceFound()
						self.parent.faceObservation = nil
					}
				}
			}

			do {
				try sequenceHandler.perform([detectFaceRequest], on: pixelBuffer)
			} catch {
				print("Failed to perform face detection: \(error)")
			}
		}
	}
}

/// A simple UIView subclass to hold the camera preview layer
class CameraPreviewView: UIView {
	override class var layerClass: AnyClass {
		AVCaptureVideoPreviewLayer.self
	}

	var previewLayer: AVCaptureVideoPreviewLayer {
		layer as! AVCaptureVideoPreviewLayer
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		previewLayer.videoGravity = .resizeAspectFill
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	weak var delegate: AVCaptureVideoDataOutputSampleBufferDelegate?
}


