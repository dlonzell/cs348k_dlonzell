import Foundation
import simd

enum CafeCounterDemoPlan {
    static let scenario = ScenarioCard(
        id: "cafe_counter_hello_world",
        setting: "Japanese cafe counter",
        learnerRole: "customer",
        sceneGoal: "Order a drink and pastry, then pay",
        localContext: "The learner is standing at the counter with a menu, pastry display, tray, cup, and card reader in reach.",
        targetInteractions: [
            "get the barista's attention",
            "indicate the menu",
            "point at the pastry display",
            "place the drink on the tray",
            "tap the payment terminal"
        ],
        expectedObjectCategories: [
            "counter",
            "menu",
            "display_case",
            "cup",
            "tray",
            "card_reader",
            "npc_marker"
        ]
    )

    static let plan = InteractionWorldPlan(
        id: "cafe_counter_interaction_world",
        scenario: scenario,
        objects: [
            WorldObjectSpec(
                id: "counter",
                displayName: "Counter",
                kind: .counter,
                position: [0, 0.62, -0.95],
                size: [0.95, 0.08, 0.52],
                color: .brown,
                isInteractive: false
            ),
            WorldObjectSpec(
                id: "menu",
                displayName: "Menu",
                kind: .menu,
                position: [-0.32, 0.70, -0.88],
                size: [0.22, 0.02, 0.30],
                color: .red,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "pastry_case",
                displayName: "Pastry Case",
                kind: .displayCase,
                position: [0.00, 0.73, -0.98],
                size: [0.26, 0.16, 0.18],
                color: .yellow,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "coffee_cup",
                displayName: "Coffee Cup",
                kind: .cup,
                position: [0.30, 0.72, -0.88],
                size: [0.08, 0.09, 0.08],
                color: .cyan,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "tray",
                displayName: "Tray",
                kind: .tray,
                position: [0.08, 0.69, -0.72],
                size: [0.30, 0.02, 0.20],
                color: .blue,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "card_reader",
                displayName: "Card Reader",
                kind: .cardReader,
                position: [0.46, 0.72, -0.98],
                size: [0.14, 0.06, 0.12],
                color: .green,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "barista_marker",
                displayName: "Barista",
                kind: .npcMarker,
                position: [0.00, 1.05, -1.35],
                size: [0.16, 0.28, 0.05],
                color: .purple,
                isInteractive: true
            )
        ],
        tasks: [
            InteractionTask(
                id: "wave_to_barista",
                instruction: "Get the barista's attention.",
                requiredObjectIds: ["barista_marker"],
                expectedInteraction: .gesture(.wave, targetId: "barista_marker")
            ),
            InteractionTask(
                id: "indicate_menu",
                instruction: "Indicate the menu to start ordering.",
                requiredObjectIds: ["menu"],
                expectedInteraction: .indicate(objectId: "menu")
            ),
            InteractionTask(
                id: "point_at_pastry_case",
                instruction: "Point at the pastry display.",
                requiredObjectIds: ["pastry_case"],
                expectedInteraction: .gesture(.point, targetId: "pastry_case")
            ),
            InteractionTask(
                id: "place_cup_on_tray",
                instruction: "Place the drink on the tray.",
                requiredObjectIds: ["coffee_cup", "tray"],
                expectedInteraction: .place(objectId: "coffee_cup", targetId: "tray")
            ),
            InteractionTask(
                id: "tap_card_reader",
                instruction: "Tap the card reader to pay.",
                requiredObjectIds: ["card_reader"],
                expectedInteraction: .tap(objectId: "card_reader")
            )
        ]
    )
}
