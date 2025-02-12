//
//  FaceBoundingView.swift
//  aiTest
//
//  Created by Peter Rogers on 10/02/2025.
//
import SwiftUI
@preconcurrency import Vision

///// A helper shape to draw a red rectangle around the detected face in SwiftUI
struct FaceBoundingView: Shape {
	let faceObservation: VNFaceObservation
	let frameSize: CGSize

	func path(in rect: CGRect) -> Path {
		var path = Path()
		let boundingBox = faceObservation.boundingBox
		
		let boxWidth = boundingBox.size.width * frameSize.width
		let boxHeight = boxWidth
		//let boxHeight = boundingBox.size.height * frameSize.height
		let boxX = (1 - boundingBox.origin.x - boundingBox.size.width) * frameSize.width
		// Vision's Y origin is from the bottom; SwiftUI's is from the top
		let boxY = (1 - boundingBox.origin.y - boundingBox.size.height) * frameSize.height

		let faceRect = CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)
		path.addRect(faceRect)

		return path
	}
}
