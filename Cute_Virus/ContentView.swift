//
//  ContentView.swift
//  Cute_Virus
//
//  Created by Peter Rogers on 10/02/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
			Rectangle()
				.fill(Color.black)
			VisionFace()
		}.edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    ContentView()
}
