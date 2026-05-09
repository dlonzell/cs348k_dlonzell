//
//  SceneToggle.swift
//  RoleplAR
//
//  Created by reactgenie-dev on 6/5/24.
//

import SwiftUI

struct SceneToggle: View {
    
    @EnvironmentObject var narrativeModel: NarrativeModel
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        
        Toggle("Show Scene", isOn: $narrativeModel.is_showing_scenes)
            .onChange(of: narrativeModel.is_showing_scenes) { _, isShowing in
                       Task {
                           if isShowing {
                               await openImmersiveSpace(id: "scenes")
                           } else {
                               await dismissImmersiveSpace()
                           }
                       }
                   }
                   .toggleStyle(.button)
        
    }
}

#Preview {
    SceneToggle()
}
