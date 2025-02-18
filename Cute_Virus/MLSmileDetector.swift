import SwiftUI
import AVFoundation
import Vision
import CoreML

class MLModelTester: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	let session = AVCaptureSession()
	private var model: SmileDectorModel?
	
	@Published var outerLipsPath: Path?
	@Published var predictionText: String = "Detecting..."
	
	override init() {
		super.init()
		setupCamera()
		loadModel()
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
	
	private func loadModel() {
		do {
			model = try SmileDectorModel(configuration: .init())
		} catch {
			print("Failed to load ML model: \(error)")
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
	
	// Process Video Frames and Predict Smiles
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
		
		let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
			guard let self = self,
				  let results = request.results as? [VNFaceObservation],
				  let firstFace = results.first,
				  let landmarks = firstFace.landmarks,
				  let rotatedOuterLips = self.getRotatedLipPoints(landmarks.outerLips, faceBoundingBox: firstFace.boundingBox, mirrored: connection.isVideoMirrored) else { return }
			
			DispatchQueue.main.async {
				self.outerLipsPath = self.createLipPath(from: rotatedOuterLips)
				self.predictSmile(using: rotatedOuterLips)
			}
		}
		
		let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
		try? handler.perform([request])
	}
	
	// Predict Smile Using Core ML
	private func predictSmile(using outerLips: [CGPoint]) {
		guard let model = model else { return }

		let features = outerLips.flatMap { [$0.x, $0.y] }
		
		do {
			let input = SmileDectorModelInput(
				Outer_L1_x: features[0], Outer_L1_y: features[1],
				Outer_L2_x: features[2], Outer_L2_y: features[3],
				Outer_L3_x: features[4], Outer_L3_y: features[5],
				Outer_L4_x: features[6], Outer_L4_y: features[7],
				Outer_L5_x: features[8], Outer_L5_y: features[9],
				Outer_L6_x: features[10], Outer_L6_y: features[11],
				Outer_L7_x: features[12], Outer_L7_y: features[13],
				Outer_L8_x: features[14], Outer_L8_y: features[15],
				Outer_L9_x: features[16], Outer_L9_y: features[17],
				Outer_L10_x: features[18], Outer_L10_y: features[19],
				Outer_L11_x: features[20], Outer_L11_y: features[21],
				Outer_L12_x: features[22], Outer_L12_y: features[23],
				Outer_L13_x: features[24], Outer_L13_y: features[25],
				Outer_L14_x: features[26], Outer_L14_y: features[27]
			)
				
			
			let prediction = try model.prediction(input: input)
			print(prediction.SmileLabel)
			let isSmiling = prediction.SmileLabel == 1
			
			DispatchQueue.main.async {
				self.predictionText = isSmiling ? "😃 Smiling!" : "😐 Not Smiling"
			}
		} catch {
			print("Prediction error: \(error)")
		}
	}
	
	// Convert Vision Bounding Box to SwiftUI Space
	private func convertBoundingBox(_ boundingBox: CGRect) -> CGRect {
		let screenWidth = UIScreen.main.bounds.width
		let screenHeight = UIScreen.main.bounds.height
		return CGRect(
			x: boundingBox.origin.x * screenWidth,
			y: (1 - boundingBox.origin.y - boundingBox.height) * screenHeight, // Flip Y-axis
			width: boundingBox.width * screenWidth,
			height: boundingBox.height * screenHeight
		)
	}
	
	// Rotate Outer Lip Points to Level Them
	private func getRotatedLipPoints(_ region: VNFaceLandmarkRegion2D?, faceBoundingBox: CGRect, mirrored: Bool) -> [CGPoint]? {
		guard let region = region else { return nil }

		let faceRect = convertBoundingBox(faceBoundingBox)
		let points = region.normalizedPoints.map { point in
			CGPoint(
				x: faceRect.origin.x + ((mirrored ? (1 - point.x) : point.x) * faceRect.width),
				y: faceRect.origin.y + ((1 - point.y) * faceRect.height)
			)
		}
		
		guard points.count >= 6 else { return nil } // Ensure enough points exist
		
		let leftCorner = points[0]
		let rightCorner = points[5]

		// Compute rotation angle
		let dx = rightCorner.x - leftCorner.x
		let dy = rightCorner.y - leftCorner.y
		let angle = atan2(dy, dx)

		return points.map { rotatePoint($0, around: leftCorner, by: -angle) }
	}

	// Apply 2D Rotation to a Point
	private func rotatePoint(_ point: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
		let translatedX = point.x - center.x
		let translatedY = point.y - center.y
		let rotatedX = translatedX * cos(angle) - translatedY * sin(angle)
		let rotatedY = translatedX * sin(angle) + translatedY * cos(angle)
		return CGPoint(x: rotatedX + center.x, y: rotatedY + center.y)
	}

	// Convert Outer Lip Landmarks to SwiftUI Path
	private func createLipPath(from points: [CGPoint]) -> Path {
		var path = Path()
		if let firstPoint = points.first {
			path.move(to: firstPoint)
			for point in points.dropFirst() {
				path.addLine(to: point)
			}
			path.closeSubpath()
		}
		return path
	}
}

// MARK: - Camera Preview
struct MLCameraPreview: UIViewRepresentable {
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

// MARK: - SwiftUI View for Testing Smile Model
struct MLModelTestView: View {
	@StateObject private var tester = MLModelTester()

	var body: some View {
		ZStack {
			MLCameraPreview(session: tester.session)
				.edgesIgnoringSafeArea(.all)

			Canvas { context, size in
				if let outerLips = tester.outerLipsPath {
					context.stroke(outerLips, with: .color(.red), lineWidth: 2)
				}
			}

			VStack {
				Text(tester.predictionText)
					.font(.largeTitle)
					.bold()
					.padding()
					.background(Color.white.opacity(0.8))
					.cornerRadius(10)

				Button("Start Session") {
					tester.startSession()
				}
				.buttonStyle(.borderedProminent)

				Button("Stop Session") {
					tester.stopSession()
				}
				.buttonStyle(.borderedProminent)
			}
			.padding(.bottom, 50)
		}
	}
}
