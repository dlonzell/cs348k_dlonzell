//
//  Constants.swift
//  RoleplAR
//
//  Created by Danilo L. Symonette  on 7/7/24.
//

import Foundation

enum Constants{
 
    /*
     OPEN AI
     */
    
    static let openAIAPIKey = "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"
    static let openAIModel = "gpt-4o-2024-05-13"
    
    /*
     NARRATIVE
     */
    
    static let newScenePrompt =

    """
    I want you to take a list of words, and come up with a scenario in which I could hear those words used or have the opportunity to use them myself. When you give me the scenario, I want you to tell me the setting (where is it? what's going on there? why are we here?), the characters (including me, the protagonist, and other characters I would interact with there or who I could watch interact with each other.), and a list of examples of different interactions that could happen where I would hear or use those words (as the protagonist). When you give lists of the interactions, make sure it's interactions between me and one of the characters. These interactions will make up the 'scenes' where users will interact. I want each character in the character list to be one person only, and I don't want more than 5 characters in a scenario. There shouldn't be more than one character in a scene, and no character should be in more than one scene. There should be a correspodning list scene_members that will let me know what character is in each scene.

    This is an example of a list of learning goals: apple, orange, banana, garlic, onion, phone, battery, drive, car, Welcome!, Thank You!, scanner, aisle, price, payment

    The following is an example of output, based on the learning goals above:
    {
      "Setting": {
        "location": "a bustling farmer's market on a sunny Saturday morning",
        "atmosphere": "vibrant and lively, with stalls selling fresh produce and artisanal goods"
      },
      "Characters": {
        
        "You": "A regular visitor to the farmer's market who enjoys exploring the variety of offerings",
        "Sophia": "A friendly vendor who sells a variety of fruits and vegetables",
        "Jack": "A fellow market-goer who often strikes up conversations with vendors and other customers",
        "Ms.Patel": "The organizer of the farmer's market who ensures everything runs smoothly",
        "Daniel": "A first-time vendor at the market who seems a bit overwhelmed by the bustling crowd"
      },
      "Scenes": [
        "You stroll through the market, browsing the colorful array of fruits and vegetables at Sophia's stall.",
        "Jack waves to you from across the market and suggests you try the fresh apple cider at another vendor's stand.",
        "Ms. Patel passes by, greeting you warmly and thanking you for your continued support of the market.",
        "After browsing around Daniel's stall, you head to his payment booth to settle the bill, chatting about the fair prices and quality of the produce."
      ]
     "Scene_Members": [
        ["Sophia"],
        ["Jack"],
        ["Ms.Patel"],
        ["Daniel"],
      ]
    }

    Make sure to generate a scenario that can incorporate as many of the words and phrases in the learning goals as possible. No matter what, do not veer from the example output format in your response. No interaction examples are necessary beyond what is asked for in the example output format.

    """
    
    static let learningObjectiveDefault = "enter a list of words or phrases that you would like to hear or practice saying"
    static let learningObjectivePrompt = "Now, generate a new scenario using the following list of learning goals, and remember to not come up with your own learning goals: "
    static let generateLearningObjectivesPrompt = "Given a description of a scenario, generate learning goals, a comma-separated list of key words and phrases that I could learn from interactions in the scenario, limited to 15 total. Keep the list to simple words and phrases that the user could learn to say or want to hear, rather than broader topics and ideas. This is an example of a list of learning goals: apple, orange, banana, garlic, onion, phone, battery, drive, car, Welcome!, Thank You!, scanner, aisle, price, payment. Now, generate a list of learning goals for the following scenario: "
    
    static let scenarioDefault = "describe a scenario you're interested in learning from"
    static let scenarioPrompt = "In addition, use the following description as inspiration for the location and atmosphere, but, once again make sure you follow the example output format: "
    
    /*
     IMAGES
     */
    static let revisionPrompt = "Given the following prompt, respond with a revised prompt that you would send to dall-e-3 to generate the desired image. Only respond with the prompt and no other extra text:"
    
    
}
