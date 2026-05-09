//
//  RoleplARApp.swift
//  RoleplAR
//
//  Created by reactgenie-dev on 4/30/24.
//

import SwiftUI

@main
struct RoleplARApp: App {


    //narrative model for holding narrative components and functions for generating them
    @State private var model = NarrativeModel()
    @State private var dialogueModel = DialogueViewModel()
    @StateObject private var interactionWorldRuntime = InteractionWorldRuntime()

    //The immersion style
    @State private var sceneImmersionStyle: ImmersionStyle = .mixed

    var body: some Scene {

        //General management window (generating narrative, showing summary, options, narrating scenes)
        WindowGroup {
            NavigationStack {
                MainMenuView()
                    .environmentObject(model)
                    .environmentObject(dialogueModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 800)

        //Handles the dialogue w/ characters in the scenes (support, suggestions, chat)
        WindowGroup(id: "dialogue"){
            DialogueView()
                .environmentObject(dialogueModel)
        }
        .defaultSize(width: 400, height: 400)

        // VLM Test Window - for testing FastVLM scene understanding
        WindowGroup(id: "vlmTest") {
            VLMTestView()
                .environmentObject(dialogueModel)
                .environmentObject(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 500, height: 600)

        // Interaction World Test Window - LLMR-inspired task queue and evaluation slice
        WindowGroup(id: "interactionWorldTest") {
            InteractionWorldTestView()
                .environmentObject(interactionWorldRuntime)
        }
        .windowStyle(.plain)
        .defaultSize(width: 760, height: 700)

        //Handles the "stage" ; placement and interaction w/ character, background, and scene images
        ImmersiveSpace(id: "scenes") {
            SceneView()
                .environmentObject(model)
                .environmentObject(dialogueModel)
        }
        .immersionStyle(selection: $sceneImmersionStyle, in: .mixed)

        // VLM Immersive Test - draggable objects with hand tracking
        ImmersiveSpace(id: "vlmImmersive") {
            #if targetEnvironment(simulator)
            SimulatorImmersiveVLMView()
                .environmentObject(dialogueModel)
            #else
            VLMImmersiveTestView()
                .environmentObject(dialogueModel)
            #endif
        }
        .immersionStyle(selection: $sceneImmersionStyle, in: .mixed)

        // Interaction World Immersive Space - generated micro-world from a plan fixture
        ImmersiveSpace(id: "interactionWorldImmersive") {
            InteractionWorldImmersiveView()
                .environmentObject(interactionWorldRuntime)
        }
        .immersionStyle(selection: $sceneImmersionStyle, in: .mixed)

        // Frame Viewer Window - for viewing captured VLM frames
        WindowGroup(id: "frameViewer") {
            FrameViewerWindow()
        }
        .windowStyle(.plain)
        .defaultSize(width: 900, height: 600)
    }
}
