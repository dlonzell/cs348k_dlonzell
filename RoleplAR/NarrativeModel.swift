//
//  NarrativeModel.swift
//  RoleplAR
//
//  Created by reactgenie-dev on 5/2/24.
//

import OpenAI
import SwiftUI
import AVFoundation
import XCAOpenAIClient

/*
 The main class for manipulating and storing the narrative
 TODO: make conform to observable 
 */
class NarrativeModel: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate, ObservableObject {
    
    /*
     APP DATA
     */
    
    //learning objectives with default for example
    @Published var learning_objectives: String = Constants.learningObjectiveDefault
    @Published var scenario_seed: String = Constants.scenarioDefault
    //narrative components
    @Published var setting: [String : String] = [:]
    @Published var scenario_summary: String = "No scene has been generated"
    @Published var hasGeneratedScene = false
    
    @Published var characters: [String : String] = [:]
    @Published var character_scene_images: [String: UIImage] = [:]
    @Published var character_preview_images: [String: UIImage] = [:]
    
    @Published var scenes: [String] = []
    @Published var scene_members: [[String]] = [[]]
    @Published var scene_images: [UIImage] = []
    
    @Published var background_image: UIImage? = nil
    
    //scene management
    @Published var is_showing_scenes: Bool = false
    @Published var current_scene_index = -1
    
    //character interaction
    @Published var is_showing_dialogue: Bool = false
    @Published var user_turn: Bool = false // who's turn it is to speak
    @Published var chat_record: [[String:String]] = [[:]] // an array of chat interactions [(user/ai):(text)]
    
    //audio handling
    var audioPlayer: AVAudioPlayer!
    var audioRecorder: AVAudioRecorder!
    var recordingSession = AVAudioSession.sharedInstance()
    var animationTimer: Timer? // may not be needed if we wont have an animation but could use the one (or similar) from the video
    var recordingTimer: Timer?
    var audioPower = 0.0
    var prevAudioPower: Double?
    var processingSpeechTask: Task<Void,Never>?
    
    var captureURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first!.appendingPathComponent ("recording.m4a")
    }
    
    var scenario_preview: String {
        let preview =
        """
        You are \(characters["You"]?.lowercased() ?? "a person"). You find yourself at \(setting["location"] ?? "a place"). It is \(setting["atmosphere"] ?? "having some atmosphere").
        """
        return preview
    }
    
    var dialoguePrompt: String {
        let prompt =
        """
        You are playing a character in a roleplaying game. You are at \(setting["location"] ?? ""). It is \(setting["atmosphere"] ?? ""). Your character is \(scene_members[current_scene_index]), \(characters[scene_members[current_scene_index].first ?? ""] ?? ""). Your job is to engage in dialogue with the user as if you were in the following situation (where you is the user) : \(scenes[current_scene_index]). When the conversation is over, based on the situation provided, make sure to say goodbye and then print *conversation ended* , even if it is over after only one message from you. Do not respond with an entire conversation, only respond to the user one message at a time.
        """
        return prompt
    }
    
    
    //openAI session (for narrative structure)
    private let openAI = OpenAI(apiToken: Constants.openAIAPIKey)
    
    //openAI session (for audio handling)
    private let client = OpenAIClient(apiKey: Constants.openAIAPIKey)
    
    /*
     FUNCTIONS FOR GENERATING NARRATIVE
     */
    
    //generate narrative components from learning objectives
    func generate_narrative() async {
        
        //variables for holding narrative info
        var response = ""
        
        //combine prompt w/ user input learning objectives
        var prompt = Constants.newScenePrompt //base prompt
        
        //error if no input
        if scenario_seed == Constants.scenarioDefault && learning_objectives == Constants.learningObjectiveDefault{
            DispatchQueue.main.async{
                self.hasGeneratedScene = false
            }
            return
        }
        //if seed, add to prompt
        if scenario_seed != Constants.scenarioDefault {
            prompt += (Constants.scenarioPrompt + scenario_seed)
            
            //if seed but no learning objectives were added, generate learning objectives
            if learning_objectives == Constants.learningObjectiveDefault{
                do{
                    let responseText = try await client.promptChatGPT(prompt: Constants.generateLearningObjectivesPrompt + scenario_seed)
                    
                    DispatchQueue.main.async{
                        self.learning_objectives = responseText
                        prompt += (Constants.learningObjectivePrompt + self.learning_objectives)
                    }
                } catch {
                    print("An error occured: \(error)")
                }
            } else {
                prompt += (Constants.learningObjectivePrompt + learning_objectives)
            }
        } else {
            prompt += (Constants.learningObjectivePrompt + learning_objectives)
        }
        
        //form query to be used in request to Chat Completions API
        print(prompt)
        let query = ChatQuery(messages: [.init(role: .system, content: "you are a helpful assistant")!, .init(role: .user, content: prompt)!], model: Constants.openAIModel)
        
        //wrap for error handling
        do {
            
            //make request
            let result = try await openAI.chats(query: query)
            
            
            //pull text response from result
            response = (result.choices[0].message.content?.string)!
            print(response)
            //try to convert response to data (for json conversion)
            if let response_data = response.data(using: .utf8){
                
                //get a json object from the data
                let jsonObject = try JSONSerialization.jsonObject(with: response_data)
                
                //set all the narrative componenents from the response
                //use dispatch queue to make sure changes to published values happen in main thread
                DispatchQueue.main.async{
                    if let narrative = jsonObject as? [String: Any] {
                        if let s = narrative["Setting"] as? [String : String]{ self.setting = s }
                        if let c = narrative["Characters"] as? [String : String]{ self.characters = c }
                        if let s = narrative["Scenes"] as? [String]{ self.scenes = s }
                        if let s_m = narrative["Scene_Members"] as? [[String]]{self.scene_members = s_m}
                        self.hasGeneratedScene = true
                    }
                }
            }
        } catch {
            print ("An error occurred: \(error)")
        }
        
        
    }
    
    func reset(){
        
        learning_objectives = ""
        
        //narrative components
        setting = [:]
        characters = [:]
        scenes = []
        scene_members = [[]]
        scenario_summary = "No scene has been generated"
        character_scene_images = [:]
        character_preview_images = [:]
        background_image = nil
        
        //scene management
        is_showing_scenes = false
        current_scene_index = 0
    }
    
    /*
     FUNCTIONS FOR GENERATING IMAGES
     TODO: re-org narrative structure so I don't need to generate all the images at once
     */
    
    func generate_images() async {
        
        //First, set the prompt to generate a background image based on the location and atmosphere
        var prompt =
        """
        For the following descriptions of location and atmosphere, generate an image of a scene
        someone at ground-level. This image should be like the backdrop for a play, and in the style of a Japanese "slice-of-life" anime. Location: \(setting["location"] ?? " "), Atmosphere: \(setting["atmosphere"] ?? " ")
        """
        
        //...and generate the main background image
        do{
            
            let query = ChatQuery(messages: [.init(role: .system, content: "you are a helpful assistant")!, .init(role: .user, content: Constants.revisionPrompt + prompt)!], model: Constants.openAIModel)
            let responseText = try await openAI.chats(query: query).choices.first?.message.content?.string
            print("Background Image Prompt: \(responseText ?? "error" ) \n")
             
            /*
            let responseText = try await client.promptChatGPT(prompt: "Given the following prompt, respond with the prompt that you would send to dall-e-3 to generate the desired image. Only respond with the prompt and no other extra text: Prompt [" + prompt + "]")
            print("Background Image Prompt: \(responseText)") // testing
            */
            
            let image = try await generate_image(prompt: responseText ?? "Show an error image for funsies", size: "1792x1024")
            DispatchQueue.main.async {
                self.background_image = image
                //print("~Background Image Loaded~")
            }
             
            
        } catch {
            print("Error generating background image \(error) ")
        }
        
        //Then, for each scene...
        for scene_num in scenes.indices{
            
            //...iterate through characters in the scene...
            for character in scene_members[scene_num]{
                
                //...skip you...
                if character != "You"{
                    
                    //... and set prompt to generate a character image based on the character description, setting, and the situation
                    prompt =
                        """
                        For the following description, generate an image of a person as you would view them from standing right in front of them, as if I could make eye contact with them through the image, when encountered in the provided location, atmosphere, and situation. It should be drawn in the style of Japanese "slice-of-life" anime. Description: \(character + ", " + (characters[character] ?? " ")), Situation: \(scenes[scene_num]), Location: \(setting["location"] ?? " "), Atmosphere: \(setting["atmosphere"] ?? " ")
                        """
                    
                    //Use the dispatch queue to set the character image, using naming convention that denotes which scene
                    do{
                        
                        let query = ChatQuery(messages: [.init(role: .system, content: "you are a helpful assistant")!, .init(role: .user, content: Constants.revisionPrompt + prompt)!], model: Constants.openAIModel)
                        let responseText = try await openAI.chats(query: query).choices.first?.message.content?.string
                        print("Character Image Prompt: \(responseText ?? "error" )\n")
                        
                        /*
                        let responseText = try await client.promptChatGPT(prompt: "Given the following prompt, enclosed in brackets, respond with the prompt that you would send to dall-e-3 to generate the desired image. Only respond with the prompt and no other extra text: Prompt [" + prompt + "]")
                        print("Character Image Prompt: \(responseText)") // TESTING
                         */
                        
                        let image = try await generate_image(prompt: responseText ?? "make an error image for funsies")
                        DispatchQueue.main.async{
                            self.character_scene_images[character + String(scene_num)] = image
                            if self.character_preview_images[character] == nil{
                                self.character_preview_images[character] = image
                            }
                            //print("~Character Image Loaded~")
                        }
                    }catch{
                        print("Error generating image for \(character): \(error)")
                    }
                }
            }
            
            //Set prompt to generate a scene image background based on situation and setting
            let prompt =
            """
            For the following descriptions of location, atmosphere, and situation, generate an image of a scene
            as it would be viewed from someone at ground-level. It should be the scene or background that is behind the character in the situation provided, and not include the characters themselves. This image should be like the backdrop for a play, and in the style of a Japanese "slice-of-life" anime. Location: \(setting["location"] ?? " "), Atmosphere: \(setting["atmosphere"] ?? " "), Situation: \(scenes[scene_num])
            """
            
            //Generate scene image for this scene
            do{
                do{
                    
                    let query = ChatQuery(messages: [.init(role: .system, content: "you are a helpful assistant")!, .init(role: .user, content: Constants.revisionPrompt + prompt)!], model: Constants.openAIModel)
                    let responseText = try await openAI.chats(query: query).choices.first?.message.content?.string
                    print("Scene Image Prompt: \(responseText ?? "error" ) \n")
                     
                    /*
                    let responseText = try await client.promptChatGPT(prompt: "Given the following prompt, enclosed in brackets, respond with the prompt that you would send to dall-e-3 to generate the desired image. Only respond with the prompt and no other extra text: Prompt [" + prompt + "]")
                    print("Scenario Background Image Prompt: \(responseText)") // TESTING
                    */
                    
                    let image = try await generate_image(prompt: responseText ?? "make an error image for funsies", size: "1792x1024")
                    DispatchQueue.main.async {
                        self.scene_images.append(image)
                        //print("~Scene Image Loaded~")
                    }
                    
                }catch{
                    print("Error generating image for Scene \(scene_num): \(error)")
                }
                
            }
        }
    }
    
    func generate_image(prompt: String, size: String = "1024x1024") async throws -> UIImage {
        
        //form request
        let url = URL(string: "https://api.openai.com/v1/images/generations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(Constants.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        //set params
        let body: [String: Any] = [
            "prompt": prompt,
            "n": 1,
            "model": "dall-e-3",
            "size": size,
            "quality": "hd",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        //make request
        let (data, _ ) = try await URLSession.shared.data(for: request)
        
        //handle response
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let imageUrlString = dataArray.first?["url"] as? String,
              let imageUrl = URL(string: imageUrlString),
              let imageData = try? Data(contentsOf: imageUrl),
              let image = UIImage(data: imageData) else {
            throw NSError (domain: "ImageGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate image"])
        }
        return image
    }
    
    /*
     FUNCTIONS FOR AUDIO HANDLING
     */
    
    override init() {
        super.init()
        do{
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            
            AVAudioApplication.requestRecordPermission { allowed in //add unowned self if needing to access state for error
                if !allowed {
                    print("Recording not allowed by the user")
                }
            }
        } catch {
            print(error)
        }
    }
    func startCaptureAudio(){
        resetAudioValues()
        //state = .recordingSpeech
        do{
            audioRecorder = try AVAudioRecorder(url: captureURL,
                                                settings: [
                                                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                                                    AVSampleRateKey: 12000,
                                                    AVNumberOfChannelsKey:1,
                                                    AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue
                                                ])
            audioRecorder.isMeteringEnabled = true
            audioRecorder.delegate = self
            audioRecorder.record()
            
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true, block: {[unowned self]_ in
                
                guard self.audioRecorder != nil else {return}
                self.audioRecorder.updateMeters()
                let power = min(1, max(0, 1 - abs(Double(self.audioRecorder.averagePower(forChannel: 0)) / 50 )))
                if self.prevAudioPower == nil {
                    self.prevAudioPower = power
                    return
                }
                if let prevAudioPower = self.prevAudioPower, prevAudioPower < 0.25 && power < 0.175 {
                    self.finishCaptureAudio()
                    return
                }
                self.prevAudioPower = power
            })
            
        }catch{
            resetAudioValues()
        }
    }
    
    
    func finishCaptureAudio(){
        resetAudioValues()
        do{
            let data = try Data(contentsOf: captureURL)
            //processingSpeechTask = processspeechTask(audioData: data)
        }catch{
            print(error)
            resetAudioValues()
        }
    }
    
    func cancelRecording(){
        resetAudioValues()
        //state = .idle
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag{
            resetAudioValues()
            //state = .idle
        }
    }
    
    func processSpeechTask(audioData: Data = Data(), text: String = " ", fromText: Bool = false) -> Task<Void, Never> {
        Task { @MainActor [unowned self] in
            
            do {
                var inputText = " "
                
                if !fromText{
                    //self.state = .processingSpeech
                    let prompt = try await client.generateAudioTransciptions(audioData: audioData)
                    
                    try Task.checkCancellation()
                    let responseText = try await client.promptChatGPT(prompt: prompt)
                    inputText = responseText
                }else{
                    inputText = text
                }
                
                try Task.checkCancellation()
                let data = try await client.generateSpeechFrom(input: inputText, voice: .alloy)
                
                try Task.checkCancellation()
                try self.playAudio(data: data)
                
            } catch {
                if Task.isCancelled {return}
                //state = .error(error)
                resetAudioValues()
            }
        }
    }
    
    func playAudio(data: Data) throws {
        //self.state = .playingSpeech
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer.isMeteringEnabled = true
        audioPlayer.delegate = self
        audioPlayer.play()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        resetAudioValues()
        //state = .idle
    }
    
    func resetAudioValues(){
        audioPower = 0
        prevAudioPower = nil
        audioRecorder?.stop()
        audioPlayer = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
    

