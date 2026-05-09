//
//  MainMenuView.swift
//  RoleplAR
//
//  Created by reactgenie-dev on 5/1/24.
//

import SwiftUI

struct MainMenuView: View {

    @EnvironmentObject private var narrative_model: NarrativeModel // the view model
    @EnvironmentObject private var dialogueModel: DialogueViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var navigateToPlay = false    //main view for menu
    @State private var hasGeneratedScene = false

    var body: some View {

        //contains the whole window
        VStack(spacing: 20){

            //exit, title, settings bar
            HStack{
                Button(action: exit){Text("  Exit  ")}
                    .padding(20)
                Spacer()
                Text("Welcome to RoleplAR").font(.extraLargeTitle)
                Spacer()
                Button("VLM Test") {
                    openWindow(id: "vlmTest")
                }
                Button("Interaction World") {
                    openWindow(id: "interactionWorldTest")
                }
                Button("VLM Immersive") {
                    Task {
                        await openImmersiveSpace(id: "vlmImmersive")
                    }
                }
                .padding(.trailing, 10)
                Button(action: open_settings) {Text("Settings")}
                    .padding(20)
            }
            //.background(.green).border(.black) //debugging
            
            Divider()
            
            // app navigation section //
            HStack(spacing: 20){
                
                //options
                VStack(){
                    Spacer()
                    //show summary
                    if hasGeneratedScene{
                        
                        if narrative_model.hasGeneratedScene == true {
                            VStack(spacing: 10){
                                
                                Text("Preview").font(.title)
                                ScrollView{
                                    Text("\(narrative_model.scenario_preview)")
                                        .padding(20)
                                }
                                .frame(width: 300, height: 350)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(20)
                                .padding(20)
                                
                            }
                        } else {
                            ProgressView("Running scene generation and loading preview ")
                        }
 
                    } else {
                    //show instructions
                        Text("Getting Started")
                            .font(.title)
                        Text("RoleplAR is a scenario-based roleplay app for language learning in Augmented Reality. \n\nOn the right, input your desired learning goals (words and phrases you would like to learn or practice) and/or a scenario you'd like to learn associated words and phrases from. At least one of these is needed for generation.\n\nWhen you're ready, hit \"Generate New Scene\" and the app will generate a simulated AR environment for you! This will also load a setting preview for you to review before pressing \"Play\", or editing your inputs before generating another new scene")
                            .padding()
                            .frame(width: 400)
                        
                    }
                    Spacer()
                    HStack{
                        
                        Button(action: {Task {
                            hasGeneratedScene = true
                            await narrative_model.generate_narrative()
                        }}){
                            Text("Generate New Scene")
                                .padding()
                                .cornerRadius(8)
                        }.padding(.trailing, 10)
                        Button(action: {navigateToPlay = true}){
                            Text("Play").padding()
                            Image(systemName:"play.fill")
                        }
                
                    }
                    Spacer()
                    
                }//end options vstack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                //background(.green).border(.black) //debugging
                
                Divider()
                
                // input section //
                VStack(spacing : 10){
                    VStack(spacing: 10){
                        
                        Text("Learning Goals").font(.title)
                        TextEditor(text: $narrative_model.learning_objectives)
                            .frame(width: 400, height: 200)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(20)
                            .padding(10)
                        
                        Text("Scenario").font(.title)
                        TextEditor(text: $narrative_model.scenario_seed)
                            .frame(width: 400, height: 200)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(20)
                            .padding(10)
                        
                    }

                }//end info vstack
                .frame(maxWidth: .infinity)
                //.background(Color.blue) //debugging
                
            }// end app navigation hstack
            .frame(maxHeight: .infinity)
            //.background(Color.green) //debugging
            
        }//end whole window vstack
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationDestination(isPresented: $navigateToPlay) {
            PlayView()
                .environmentObject(narrative_model)
                .environmentObject(dialogueModel)
        }
        //.background(Color.gray) //debugging
    }
    
    func exit(){
        print("exit")
    }
    func open_settings() {
        print("open settings")
    }
}

#Preview (){
    MainMenuView()
        .environmentObject(NarrativeModel())
        .environmentObject(DialogueViewModel())
        .glassBackgroundEffect()
        .frame(width: 1000)
}
