import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation

struct PlayView: View {
    
    //get narrative model
    @EnvironmentObject var narrativeModel: NarrativeModel
    @EnvironmentObject var dialogueModel: DialogueViewModel
    //gives access to open immersive space
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    
    //bools for triggering views
    @State private var showSummary = true
    @State private var isLoadingImages = true
    
    //variables for managing audio
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var isSpeaking = false
    @State private var textToSpeak = ""
    
    var body: some View {
        VStack {
            
            if showSummary {
                
                //window w/ general setting summary on the left, characters on the right
                HStack {
                    
                    //background image and setting summary
                    VStack {
                        
                        //background image
                        if let backgroundImage = narrativeModel.background_image {
                            
                            Image(uiImage: backgroundImage)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(8)
                                .frame(width: 350, height: 350)
                            
                        }else{
                            ProgressView("Loading...")
                        }
                        
                        //setting summary
                        Text("...replacing summary...")
                            .padding(20)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
                    
                    Divider()
                    
                    //list of character images + corresponding descriptions
                    ScrollView {
                        VStack {
    
                            //character images and descriptions
                            ForEach(narrativeModel.characters.keys.sorted(), id: \.self) { character in
                                if character != "You"{
                                    HStack {
                                        
                                        //character images
                                        if let image = narrativeModel.character_preview_images[character] {
                                            
                                            Image(uiImage: image)
                                                .resizable()
                                                .frame(width: 100, height: 100)
                                                .cornerRadius(8)
                                            
                                        } else {
                                            
                                            ProgressView("...")
                                                .padding(10)
                                            
                                        }
                                        
                                        //character descriptions
                                        VStack(alignment: .leading) {
                                            
                                            Text(character)
                                                .font(.headline)
                                                .padding(5)
                                            Text(narrativeModel.characters[character] ?? "")
                                                .frame(width: 350, alignment: .leading)
                                        }
                                    }
                                    .padding(20)
                                }
                            }
                            
                        } //end VStack
                    }//end ScrollView
                    .frame(maxWidth: .infinity)
                }
                .padding()
                
                if isLoadingImages{
                    ProgressView("Generating Scene Content...")
                        .padding(10)
                }else{
            
                    Button("Proceed") {
                        
                        //switch to scene descriptions and narrator
                        showSummary = false
                        
                        /* removed when testing just the narrator*/
                         Task {
                            await openImmersiveSpace(id: "scenes")
                         }
                        
                    }
                    .padding(10)
                }
            } else {
                //TODO: show the character summary and description for those in the scene in this window (?) 
                //Text description of what's goign on in the scene, read aloud by the narrator, + buttons for navigating the scenes
                VStack {
                    
                    ScrollView{
                        //whatever the narrator will be saying
                        Text(textToSpeak)
                            .frame(width: 550, alignment: .leading)
                    }
                    .frame(width: 600, height: 100)
                    
                    HStack {
                        
                        /*removed when demoing the real thing*/
                        //SceneToggle()
                        
                        //navigate between scenes
                        if narrativeModel.current_scene_index > 0 {
                            Button("Previous") {
                                narrativeModel.current_scene_index -= 1
                            }
                        }
                        if narrativeModel.current_scene_index < narrativeModel.scenes.count - 1 {
                            Button("Next") {
                                narrativeModel.current_scene_index += 1
                            }
                        }
                    }
                    .padding(20)
                    //background(.green).border(.black)
                }.padding(10)
            }
        }
        .onAppear {
            /*removed when only testing narrator*/
            loadImages()
        }
        //when user is satisfied w/ summary, proceed to the narrative experience
        .onChange(of: showSummary){
            
            //Resize the parent window
            withAnimation{
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.Vision(size: CGSize(width:650, height: 300)))
                }
            }
            
            //set up scenario priming to start
            textToSpeak = "You are \(narrativeModel.characters["You"]?.lowercased() ?? "a person"). You find yourself at \(narrativeModel.setting["location"] ?? "a place"). It is \(narrativeModel.setting["atmosphere"] ?? "having some atmosphere")."
            narrativeModel.processingSpeechTask = narrativeModel.processSpeechTask(text: textToSpeak, fromText: true)
            
        }
        //when scene changes, update narrator blurb
        .onChange(of: narrativeModel.current_scene_index){
            
            //set up textToSpeak synthesis for narrator
            if narrativeModel.current_scene_index != -1 {
                
                //if not the intro scene, start dialogue
                if !narrativeModel.is_showing_dialogue {
                    openWindow(id: "dialogue")
                    narrativeModel.is_showing_dialogue.toggle() // TODO: move to dialogueViewModel
                }
                textToSpeak = narrativeModel.scenes[narrativeModel.current_scene_index]
            }
            narrativeModel.processingSpeechTask = narrativeModel.processSpeechTask(text: textToSpeak, fromText: true)
            
            //clear previous messages, then load new dialogue
            dialogueModel.messages = []
            dialogueModel.sendMessage(role:.system, content: narrativeModel.dialoguePrompt)
        }
    }
    
    private func loadImages() {
        Task {
            isLoadingImages = true
            await narrativeModel.generate_images()
            isLoadingImages = false
            print("~DONE LOADING IMAGES~")
        }
    }
}
