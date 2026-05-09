//
//  SceneView.swift
//  RoleplAR
//
//  Created by reactgenie-dev on 6/4/24.
//

import SwiftUI
import RealityKit

/*
    TODO: explore managing content via root node
    TODO: make more efficient - do we need current_scene_index?
 */
struct SceneView: View {
    
    @EnvironmentObject var narrative_model: NarrativeModel
    @EnvironmentObject var dialogueModel: DialogueViewModel
    @State private var current_scene_index: Int = -1
    
    var body: some View {
        
        RealityView { content /*, attachments*/ in
            
            //at start, generate background image only and no characters
            if narrative_model.current_scene_index == -1 {
                
                content.add(generate_background(image: narrative_model.background_image!))
                
            } else {
                
                //generate the background image for the scene
                content.add(generate_background(image: narrative_model.scene_images[narrative_model.current_scene_index]))
                
                //generate the characters for the scene
                for character in generate_characters() {
                    content.add(character)
                    /*
                    if let character_attachment = attachments.entity(for: "dialogue_window"){
                        character_attachment.position = [0, -0.1, 0]
                        character.addChild(character_attachment)
                    }
                     */
                }
            }
            
        } update : { content /*, attachments*/ in
            
            print("update called")
            if narrative_model.current_scene_index != -1 {
                
                //remove old entitites
                content.entities.removeAll()
                
                //add new ones
                content.add(generate_background(image: narrative_model.scene_images[narrative_model.current_scene_index]))
                for character in generate_characters() {
                    content.add(character)
                    /*
                    if let character_attachment = attachments.entity(for: "dialogue_window"){
                        character_attachment.position = [0.55, 0, 0]
                        character.addChild(character_attachment)
                    }
                    */
                }
            }
            
        } /*attachments: {
            
            Attachment(id: "dialogue_window"){
                DialogueView()
                    .environmentObject(dialogueModel)
                    .frame(maxWidth: 400)
                    .glassBackgroundEffect()
            }

            
        }*/
        .onChange(of:narrative_model.current_scene_index){
            
            print("onChange called")
            current_scene_index = narrative_model.current_scene_index
        }
        
    }
    
    func generate_background(image: UIImage) -> ModelEntity {
        
        //creating the texture to be on the mesh
        let texture = create_texture_resource(from: image)
        
        //creating the 3D resource to be displayed
        let shapeMesh = MeshResource.generatePlane(width: 5, height: 3)
        
        //Setting up the material of the shape
        var material = UnlitMaterial()
        material.color = PhysicallyBasedMaterial.BaseColor(texture: .init(texture!))
        
        //Create the model entity to idsplay the shape mesh while setting up it's materials
        let model = ModelEntity(mesh: shapeMesh, materials: [material])
        model.position = [0, 1.5, -5]
        
        return model
    }
    
    /*
        TODO: revise spacing for rendering of multiple characters (or revise image generation to limit characters) 
     */
    func generate_characters() -> [ModelEntity]{
        
        var chars: [ModelEntity] = []
        
        var count = 0
        for char_name in narrative_model.scene_members[narrative_model.current_scene_index]{
            
            if char_name != "You"{
                
                //creating the texture to be on the mesh
                let texture = create_texture_resource(from: narrative_model.character_scene_images[char_name + String(narrative_model.current_scene_index)]!)
                
                //creating the 3D resource to be displayed
                let shapeMesh = MeshResource.generatePlane(width: 0.5, height: 0.5)
                
                //setting up the material of the shape
                var material = UnlitMaterial()
                material.color = PhysicallyBasedMaterial.BaseColor(texture: .init(texture!))
                
                //create the model entity to display the shape mesh while setting up it's materials
                let model = ModelEntity(mesh: shapeMesh, materials: [material])
                
                //position based on how many characters are in the scene
                if count == 1 {
                    
                    chars[0].position = [1, 1.5, -2]
                    model.position = [-1, 1.5, -2]
                    count += 1
                    
                } else {
                    
                    model.position = [0, 1.5, -2]
                    count += 1
                    
                }
                
                chars.append(model)
            }
        }
        
        return chars
    }
    
    func create_texture_resource(from image: UIImage) -> TextureResource? {
        guard let cgImage = image.cgImage else{
            print("Failed to get CGImage from UIImage")
            return nil
        }
        do{
            let texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
            return texture
        } catch {
            print ("Failed to create texture resource: \(error)")
            return nil
        }
    }
}
#Preview {
    SceneView()
}
