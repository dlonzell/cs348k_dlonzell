//
//  DialogueView.swift
//  RoleplAR
//
//  Created by Danilo L. Symonette  on 7/5/24.
//

import SwiftUI

struct DialogueView: View {
    @EnvironmentObject var dialogueModel: DialogueViewModel
    var body: some View {

        VStack{
            ScrollView{
                ForEach(dialogueModel.messages.filter({$0.role != .system}), id: \.id){ message in
                    messageView(message: message)
                }
                
            }
            HStack{
                TextField("Enter a message...", text: $dialogueModel.currentInput)
                Button{
                    dialogueModel.sendMessage()
                } label: {
                    Text("Send")
                }
            }
        }
        .padding()

    }
    
    func messageView(message: Message) -> some View{
        HStack{
            if message.role == .user {Spacer()}
            Text(message.content)
            if message.role == .assistant {Spacer()}
        }
    }
}

#Preview {
    DialogueView()
}
