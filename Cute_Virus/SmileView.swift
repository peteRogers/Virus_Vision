//
//  SmileView.swift
//  Cute_Virus
//
//  Created by Peter Rogers on 11/02/2025.
//

import SwiftUI
import AVFoundation
import Vision
import CoreImage

struct SmileDetectionView: View {
	@StateObject private var cameraModel = CameraModel()

	var body: some View {
		ZStack {
			SmileCameraPreview(session: cameraModel.session)
				.edgesIgnoringSafeArea(.all)

			VStack {
				Spacer()
				Text(cameraModel.smileStatus)
					.font(.title)
					.padding()
					.background(cameraModel.smileDetected ? Color.green.opacity(0.7) : Color.black.opacity(0.7))
					.foregroundColor(.white)
					.cornerRadius(10)
					.padding(.bottom, 50)
			}
		}
		.onAppear {
			cameraModel.startSession()
		}
		.onDisappear {
			cameraModel.stopSession()
		}
	}
}

// MARK: - Camera Model for Smile Detection
class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	let session = AVCaptureSession()
	private let ciContext = CIContext()
	
	@Published var smileStatus: String = "🙂 No Smile"
	@Published var smileDetected: Bool = false
	
	override init() {
		super.init()
		setupCamera()
	}
	
	private func setupCamera() {
		session.sessionPreset = .high
		guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
			  let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
			print("Failed to access the camera")
			return
		}
		
		if session.canAddInput(videoInput) {
			session.addInput(videoInput)
		}
		
		let videoOutput = AVCaptureVideoDataOutput()
		videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
		
		if session.canAddOutput(videoOutput) {
			session.addOutput(videoOutput)
		}
	}
	
	func startSession() {
		DispatchQueue.global(qos: .background).async {
			self.session.startRunning()
		}
	}
	
	func stopSession() {
		session.stopRunning()
	}
	
	// Process Camera Frames
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
		
		let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
			guard let self = self,
				  let results = request.results as? [VNFaceObservation],
				  let firstFace = results.first else {
				DispatchQueue.main.async {
					self?.smileStatus = "No Face Detected"
					self?.smileDetected = false
				}
				return
			}
			
			let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
			let faceBounds = self.convertBoundingBox(firstFace.boundingBox, in: ciImage)
			
			if let faceImage = self.croppedFace(from: ciImage, faceBounds: faceBounds) {
				print("bounding found")
				self.detectSmile(in: faceImage)
			}
		}
		
		let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
		try? handler.perform([request])
	}
	
	// Detect Smile using CIDetector
	private func detectSmile(in faceImage: CIImage) {
		let detectorOptions: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
		let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: detectorOptions)
		let faces = faceDetector?.features(in: faceImage) as? [CIFaceFeature] ?? []
		print(faces)
		DispatchQueue.main.async {
			if let face = faces.first, face.hasSmile {
				self.smileStatus = "😁 Smiling!"
				self.smileDetected = true
			} else {
				self.smileStatus = "🙂 No Smile"
				self.smileDetected = false
			}
		}
	}
	
	// Convert Vision bounding box to CIImage coordinates
	private func convertBoundingBox(_ boundingBox: CGRect, in image: CIImage) -> CGRect {
		let width = image.extent.width
		let height = image.extent.height

		let x = boundingBox.origin.x * width
		let y = (1 - boundingBox.origin.y - boundingBox.height) * height
		let w = boundingBox.width * width
		let h = boundingBox.height * height

		return CGRect(x: x, y: y, width: w, height: h)
	}
	
	// Crop Face Region from CIImage
	private func croppedFace(from image: CIImage, faceBounds: CGRect) -> CIImage? {
		return image.cropped(to: faceBounds)
	}
}

// MARK: - Camera Preview for SwiftUI
struct SmileCameraPreview: UIViewRepresentable {
	let session: AVCaptureSession
	
	func makeUIView(context: Context) -> UIView {
		let view = UIView(frame: UIScreen.main.bounds)
		let previewLayer = AVCaptureVideoPreviewLayer(session: session)
		previewLayer.videoGravity = .resizeAspectFill
		previewLayer.frame = view.bounds
		view.layer.addSublayer(previewLayer)
		return view
	}
	
	func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Preview
struct SmileDetectionView_Previews: PreviewProvider {
	static var previews: some View {
		SmileDetectionView()
	}
}
