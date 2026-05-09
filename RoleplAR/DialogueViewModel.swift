//
//  DialogueViewModel.swift
//  RoleplAR
//
//  Created by Danilo L. Symonette  on 7/7/24.
//

import Foundation
class DialogueViewModel: ObservableObject {
    
    @Published var messages: [Message] = []
    @Published var currentInput: String = ""
    
    private let openAIService = OpenAIService()
    func sendMessage(role: SenderRole = .user, content: String = "") {
        
        let newMessage = Message(id: UUID(), role: role, content: content == "" ? currentInput : content, createAt: Date())
        messages.append(newMessage)
        currentInput = ""
        
        Task{
            let response = await openAIService.sendMessage(messages: messages)
            guard let receivedOpenAIMessage = response?.choices.first?.message else {
                print("Had no received message")
                return
            }
            let receivedMessage = Message(id:UUID(), role: receivedOpenAIMessage.role, content: receivedOpenAIMessage.content, createAt: Date())
            await MainActor.run {
                messages.append(receivedMessage)
            }

        }
    }
    
    func revisePrompt(prompt: String) -> String {
        
        
        
        return ""
    }
}

struct Message: Decodable {
    let id: UUID
    let role: SenderRole
    let content: String
    let createAt: Date
    
}
