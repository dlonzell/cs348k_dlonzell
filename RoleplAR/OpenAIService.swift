//
//  OpenAIService.swift
//  RoleplAR
//
//  Created by Danilo L. Symonette  on 7/7/24.
//

import Foundation
import Alamofire

class OpenAIService{
    
    private let chatURL = "https://api.openai.com/v1/chat/completions"
    private let imageURL = "https://api.openai.com/v1/images/generations"
    
    func sendMessage(messages: [Message]) async -> OpenAIChatResponse? {
        let openAIMessages = messages.map({OpenAIChatMessage(role: $0.role, content: $0.content)})
        let body = OpenAIChatBody(model: Constants.openAIModel, messages: openAIMessages )
        let headers: HTTPHeaders = [
            "Authorization" : "Bearer \(Constants.openAIAPIKey)"
        ]
        return try? await AF.request(chatURL, method: .post, parameters: body, encoder: .json, headers: headers).serializingDecodable(OpenAIChatResponse.self).value
    }
    
}


/*
 CHAT
 */

enum SenderRole : String, Codable {
    case system
    case user
    case assistant
}

struct OpenAIChatBody: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
}

struct OpenAIChatResponse: Decodable {
    let choices : [OpenAIChatChoice]
}

struct OpenAIChatChoice: Decodable {
    let message: OpenAIChatMessage
}

struct OpenAIChatMessage : Codable {
    let role: SenderRole
    let content: String
}
