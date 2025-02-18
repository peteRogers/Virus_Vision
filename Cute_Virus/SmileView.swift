import SwiftUI
import AVFoundation
import Vision

struct SmileDetectionView: View {
	@StateObject private var cameraModel = CameraModel()

	var body: some View {
		ZStack {
			SmileCameraPreview(session: cameraModel.session)
				.edgesIgnoringSafeArea(.all)

			Canvas { context, size in
				if let outerLips = cameraModel.outerLipsPath {
					context.stroke(outerLips, with: .color(.red), lineWidth: 2)
				}
				if let innerLips = cameraModel.innerLipsPath {
					context.stroke(innerLips, with: .color(.blue), lineWidth: 2)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.onAppear {
			cameraModel.startSession()
		}
		.onDisappear {
			cameraModel.stopSession()
		}
	}
}

// MARK: - Camera Model for Lip Detection
class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	let session = AVCaptureSession()
	
	@Published var outerLipsPath: Path?
	@Published var innerLipsPath: Path?

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
		
		let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
			guard let self = self,
				  let results = request.results as? [VNFaceObservation],
				  let firstFace = results.first,
				  let landmarks = firstFace.landmarks else {
				DispatchQueue.main.async {
					self?.outerLipsPath = nil
					self?.innerLipsPath = nil
				}
				return
			}
			
			self.extractLipPaths(from: landmarks, faceBoundingBox: firstFace.boundingBox)
		}
		
		let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
		try? handler.perform([request])
	}
	
	// Convert Lip Landmarks to SwiftUI Paths
	private func extractLipPaths(from landmarks: VNFaceLandmarks2D, faceBoundingBox: CGRect) {
		DispatchQueue.main.async {
			if let outerLips = landmarks.outerLips {
				self.outerLipsPath = self.createLipPath(from: outerLips, faceBoundingBox: faceBoundingBox)
			}
			if let innerLips = landmarks.innerLips {
				self.innerLipsPath = self.createLipPath(from: innerLips, faceBoundingBox: faceBoundingBox)
			}
		}
	}
	
	// Create a SwiftUI Path from VNFaceLandmarkRegion2D
	private func createLipPath(from region: VNFaceLandmarkRegion2D, faceBoundingBox: CGRect) -> Path {
		var path = Path()
		let faceRect = convertBoundingBox(faceBoundingBox)
		
		let points = region.normalizedPoints.map { point in
			CGPoint(
				x: faceRect.origin.x + (point.x * faceRect.width),
				y: faceRect.origin.y + (point.y * faceRect.height)
			)
		}
		
		if let firstPoint = points.first {
			path.move(to: firstPoint)
			for point in points.dropFirst() {
				path.addLine(to: point)
			}
			path.closeSubpath()
		}
		
		return path
	}
	
	// Convert Vision bounding box to SwiftUI coordinate space
	private func convertBoundingBox(_ boundingBox: CGRect) -> CGRect {
		let screenWidth = UIScreen.main.bounds.width
		let screenHeight = UIScreen.main.bounds.height
		return CGRect(
			x: boundingBox.origin.x * screenWidth,
			y: (1 - boundingBox.origin.y - boundingBox.height) * screenHeight,
			width: boundingBox.width * screenWidth,
			height: boundingBox.height * screenHeight
		)
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
struct LipDetectionView_Previews: PreviewProvider {
	static var previews: some View {
		SmileDetectionView()
	}
}
