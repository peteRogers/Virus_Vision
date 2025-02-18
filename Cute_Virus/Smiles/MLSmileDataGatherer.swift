import SwiftUI
import AVFoundation
import Vision

class LandmarkExtractor: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	let session = AVCaptureSession()
	private var csvData: [[String]] = [["ImageName"] +
		(1...14).flatMap { ["Outer_L\($0)_x", "Outer_L\($0)_y"] } + ["SmileLabel"]
	]
	
	@Published var outerLipsPath: Path?
	@Published var captureStatus: String = "Press Start to Begin"
	@Published var isSessionRunning = false
	
	private var lastCapturedFeatures: [String] = [] // Stores last captured features for labeling

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
			DispatchQueue.main.async {
				self.captureStatus = "Recording... Label Frames Below"
				self.isSessionRunning = true
			}
		}
	}
	
	func stopSession() {
		session.stopRunning()
		isSessionRunning = false
		saveCSV()
	}
	
	// Capture Frames and Extract Outer Lip Landmarks
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
				print(self.outerLipsPath?.description)
			}

			let features = rotatedOuterLips.flatMap { ["\($0.x)", "\($0.y)"] }
			
			DispatchQueue.main.async {
				self.lastCapturedFeatures = features
			}
		}
		
		let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
		try? handler.perform([request])
	}
	
	// Label the captured frame and append to CSV
	func labelFrame(as smile: Bool) {
		guard !lastCapturedFeatures.isEmpty else { return }
		
		let label = smile ? "1" : "0"
		
		// Make sure we are appending only the required data + label
		var rowData = lastCapturedFeatures
		rowData.append(label)  // Append only the label as the last column
		
		csvData.append(["Frame\(csvData.count)"] + rowData)
		
		print("Labeled Frame\(csvData.count - 1) as \(smile ? "Smile 😃" : "Not Smile 😐")")
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

	// Save Data to CSV File
	private func saveCSV() {
		let fileName = "trainingLips.csv"
		let filePath = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
		let csvString = csvData.map { $0.joined(separator: ",") }.joined(separator: "\n")
		do {
			try csvString.write(to: filePath, atomically: true, encoding: .utf8)
			DispatchQueue.main.async {
				self.captureStatus = "CSV Saved: \(filePath.absoluteString)"
				print("CSV saved at \(filePath.absoluteString)")
			}
		} catch {
			DispatchQueue.main.async {
				self.captureStatus = "Failed to save CSV"
			}
			print("Error saving CSV: \(error)")
		}
	}
}

// MARK: - Camera Preview
struct LandmarkCameraPreview: UIViewRepresentable {
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

// MARK: - SwiftUI View with Labeling Buttons
struct LandmarkExtractionView: View {
	@StateObject private var extractor = LandmarkExtractor()

	var body: some View {
		ZStack {
			LandmarkCameraPreview(session: extractor.session)
				.edgesIgnoringSafeArea(.all)

			Canvas { context, size in
				if let outerLips = extractor.outerLipsPath {
					context.stroke(outerLips, with: .color(.red), lineWidth: 2)
				}
			}

			VStack {
				Text(extractor.captureStatus)
					.padding()
				
				Button("Start Session") {
					extractor.startSession()
				}
				.buttonStyle(.borderedProminent)

				HStack {
					Button("Not Smile 😐") {
						extractor.labelFrame(as: false)
					}
					.buttonStyle(.borderedProminent)

					Button("Smile 😃") {
						extractor.labelFrame(as: true)
					}
					.buttonStyle(.borderedProminent)
				}

				Button("Stop and Save CSV") {
					extractor.stopSession()
				}
				.buttonStyle(.borderedProminent)
			}
			.padding(.bottom, 50)
		}
	}
}
