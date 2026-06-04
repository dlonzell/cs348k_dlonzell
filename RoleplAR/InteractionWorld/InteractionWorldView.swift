import SwiftUI
import RealityKit
import UIKit

private enum ScenarioRunnerMode: String, CaseIterable, Identifiable {
    case cafeBaseline
    case convenienceStore
    case marketStand
    case cafeArrivalSeating
    case cafeOrdering
    case cafePayingCheck
    case clothingBrowseCompare
    case clothingTryingOn
    case stationTicketing
    case shrinePurification
    case editable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cafeBaseline:
            return "Cafe baseline"
        case .convenienceStore:
            return "Convenience store"
        case .marketStand:
            return "Market stand"
        case .cafeArrivalSeating:
            return "Cafe arrival seating"
        case .cafeOrdering:
            return "Cafe ordering"
        case .cafePayingCheck:
            return "Cafe paying check"
        case .clothingBrowseCompare:
            return "Clothing browse compare"
        case .clothingTryingOn:
            return "Clothing trying on"
        case .stationTicketing:
            return "Station ticketing"
        case .shrinePurification:
            return "Shrine purification"
        case .editable:
            return "Editable scenario"
        }
    }
}

private enum GenerationPipelineDisplayStage {
    case objects
    case tasks
    case validation
}

enum PrototypeScenarioCards {
    static let convenienceStore = ScenarioCard(
        id: "japanese_convenience_store",
        setting: "Japanese convenience store",
        learnerRole: "customer",
        sceneGoal: "Buy a snack and pay at the register",
        localContext: "The learner is standing near a compact counter with snacks, a shopping basket, a wallet, a payment terminal, and a cashier marker in reach.",
        targetInteractions: [
            "pick up a snack",
            "place the snack in the shopping basket",
            "indicate the payment terminal",
            "tap the payment terminal",
            "wave goodbye to the cashier"
        ],
        expectedObjectCategories: [
            "counter",
            "snack",
            "basket",
            "wallet",
            "card_reader",
            "npc_marker"
        ]
    )

    static let convenienceStoreRawPlan = InteractionWorldPlan(
        id: "japanese_convenience_store_demo_raw",
        scenario: convenienceStore,
        objects: [
            WorldObjectSpec(
                id: "snack_chips",
                displayName: "Bag of Chips",
                description: "Small bag of chips the learner can pick up",
                kind: .generic(category: "smallObject"),
                position: [-1.2, 0.15, 0.6],
                size: [0.32, 0.28, 0.22],
                color: .red,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "shopping_basket",
                displayName: "Shopping Basket",
                description: "Open basket for the snack",
                kind: .generic(category: "container"),
                position: [1.0, 1.0, 0.4],
                size: [0.50, 0.34, 0.42],
                color: .blue,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "payment_terminal",
                displayName: "Payment Terminal",
                description: "Tap-to-pay terminal",
                kind: .cardReader,
                position: [0.0, 0.0, 1.4],
                size: [0.25, 0.18, 0.20],
                color: .green,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "cashier_marker",
                displayName: "Cashier",
                description: "Marker for the cashier",
                kind: .npcMarker,
                position: [0.0, 0.0, 0.0],
                size: [0.10, 0.28, 0.10],
                color: .purple,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "store_menu",
                displayName: "Snack Menu",
                description: "Upright sign listing snack options",
                kind: .menu,
                position: [0.0, 0.0, 0.0],
                size: [0.42, 0.50, 0.06],
                color: .yellow,
                isInteractive: true
            )
        ],
        tasks: [
            InteractionTask(
                id: "pick_up_snack",
                instruction: "Pick up the bag of chips.",
                requiredObjectIds: ["snack_chips"],
                expectedInteraction: .tap(objectId: "snack_chips")
            ),
            InteractionTask(
                id: "place_snack",
                instruction: "Place the bag of chips in the shopping basket.",
                requiredObjectIds: ["snack_chips", "shopping_basket"],
                expectedInteraction: .place(objectId: "snack_chips", targetId: "shopping_basket")
            ),
            InteractionTask(
                id: "indicate_terminal",
                instruction: "Indicate the payment terminal.",
                requiredObjectIds: ["payment_terminal"],
                expectedInteraction: .indicate(objectId: "payment_terminal")
            ),
            InteractionTask(
                id: "pay",
                instruction: "Tap the payment terminal to pay.",
                requiredObjectIds: ["payment_terminal"],
                expectedInteraction: .tap(objectId: "payment_terminal")
            ),
            InteractionTask(
                id: "wave_cashier",
                instruction: "Wave goodbye to the cashier.",
                requiredObjectIds: ["cashier_marker"],
                expectedInteraction: .gesture(.wave, targetId: "cashier_marker")
            )
        ]
    )

    static let marketStand = ScenarioCard(
        id: "farmers_market_stand",
        setting: "Farmer's market stand",
        learnerRole: "shopper",
        sceneGoal: "Choose fruit, pay, and leave with the bag",
        localContext: "The learner is standing at a market stall with fruit baskets, a counter, a bagging area, a payment reader, and a vendor marker nearby.",
        targetInteractions: [
            "pick up a fruit",
            "place the fruit on the counter",
            "tap the payment reader",
            "place the fruit in a bag",
            "wave goodbye to the vendor"
        ],
        expectedObjectCategories: [
            "counter",
            "fruit",
            "fruit_basket",
            "bag",
            "card_reader",
            "npc_marker"
        ]
    )

    static let marketStandRawPlan = InteractionWorldPlan(
        id: "farmers_market_stand_demo_raw",
        scenario: marketStand,
        objects: [
            WorldObjectSpec(
                id: "market_counter",
                displayName: "Market Counter",
                description: "Counter at the front of the market stand",
                kind: .counter,
                position: [1.3, 0.2, 0.5],
                size: [0.80, 0.08, 0.42],
                color: .brown,
                isInteractive: false
            ),
            WorldObjectSpec(
                id: "apple",
                displayName: "Apple",
                description: "Fruit the learner can pick up",
                kind: .generic(category: "smallObject"),
                position: [-0.9, 1.0, 0.8],
                size: [0.18, 0.18, 0.18],
                color: .red,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "paper_bag",
                displayName: "Paper Bag",
                description: "Shopping bag for the fruit",
                kind: .generic(category: "container"),
                position: [1.1, 0.0, -0.2],
                size: [0.28, 0.28, 0.22],
                color: .yellow,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "payment_reader",
                displayName: "Payment Reader",
                description: "Reader for card payment",
                kind: .cardReader,
                position: [-1.4, 0.0, 1.2],
                size: [0.22, 0.10, 0.16],
                color: .green,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "vendor_marker",
                displayName: "Vendor",
                description: "Marker for the market vendor",
                kind: .npcMarker,
                position: [0.0, 0.0, 0.0],
                size: [0.12, 0.30, 0.12],
                color: .purple,
                isInteractive: true
            )
        ],
        tasks: [
            InteractionTask(
                id: "pick_up_fruit",
                instruction: "Pick up the apple.",
                requiredObjectIds: ["apple"],
                expectedInteraction: .tap(objectId: "apple")
            ),
            InteractionTask(
                id: "place_fruit_on_counter",
                instruction: "Place the apple on the market counter.",
                requiredObjectIds: ["apple", "market_counter"],
                expectedInteraction: .place(objectId: "apple", targetId: "market_counter")
            ),
            InteractionTask(
                id: "tap_reader",
                instruction: "Tap the payment reader.",
                requiredObjectIds: ["payment_reader"],
                expectedInteraction: .tap(objectId: "payment_reader")
            ),
            InteractionTask(
                id: "bag_fruit",
                instruction: "Place the apple in the paper bag.",
                requiredObjectIds: ["apple", "paper_bag"],
                expectedInteraction: .place(objectId: "apple", targetId: "paper_bag")
            ),
            InteractionTask(
                id: "wave_vendor",
                instruction: "Wave goodbye to the vendor.",
                requiredObjectIds: ["vendor_marker"],
                expectedInteraction: .gesture(.wave, targetId: "vendor_marker")
            )
        ]
    )

    static let cafeArrivalSeating = ScenarioCard(
        id: "cafe_arrival_seating",
        setting: "Cafe entrance with a host stand and a couple of small tables",
        learnerRole: "customer arriving to be seated",
        sceneGoal: "Greet the host and take the open table you're offered",
        localContext: "A host stand and two small tables are within reach; one table is open. A host marker stands behind the stand.",
        targetInteractions: [
            "greet the host",
            "tell the host how many people are in your party",
            "follow the host to your table",
            "sit at the open table"
        ],
        expectedObjectCategories: ["counter", "flatSurface", "npc_marker"]
    )

    static let cafeOrdering = ScenarioCard(
        id: "cafe_ordering",
        setting: "Cafe counter with a menu board and a pastry display",
        learnerRole: "customer ordering",
        sceneGoal: "Order a drink and a pastry, then confirm with the barista",
        localContext: "A counter holds an upright menu board and a pastry display case; a barista marker stands behind it.",
        targetInteractions: [
            "look at the drink on the menu",
            "choose the pastry in the display case",
            "tell the barista how many you want",
            "confirm your order"
        ],
        expectedObjectCategories: ["counter", "menu", "display_case", "npc_marker"]
    )

    static let cafePayingCheck = ScenarioCard(
        id: "cafe_paying_check",
        setting: "Cafe counter at the end of a meal",
        learnerRole: "customer paying",
        sceneGoal: "Pay the check and collect your receipt",
        localContext: "A small tray with the bill sits on the counter next to a card reader; a receipt is produced after payment.",
        targetInteractions: [
            "request the check",
            "place your card on the tray",
            "tap the card reader to pay",
            "take your receipt and change"
        ],
        expectedObjectCategories: ["counter", "bill_tray", "payment_card", "card_reader", "receipt", "change"]
    )

    static let clothingBrowseCompare = ScenarioCard(
        id: "clothing_browse_compare",
        setting: "Clothing store display table with folded jackets",
        learnerRole: "shopper browsing jackets",
        sceneGoal: "Compare two jackets and tell the clerk which you prefer",
        localContext: "A display table holds two folded jackets in different colors; a clerk marker stands nearby.",
        targetInteractions: [
            "point at the first jacket",
            "ask the clerk about the color and size",
            "compare the two jackets side by side",
            "tell the clerk you like the first one"
        ],
        expectedObjectCategories: ["counter", "smallObject", "smallObject", "npc_marker"]
    )

    static let clothingTryingOn = ScenarioCard(
        id: "clothing_trying_on",
        setting: "Clothing store fitting area",
        learnerRole: "shopper trying on a jacket",
        sceneGoal: "Try on a jacket and check the fit",
        localContext: "A jacket rests on a table next to a fitting hook and a small upright mirror; a clerk marker is nearby.",
        targetInteractions: [
            "pick up the jacket",
            "carry it to the fitting room",
            "try the jacket on",
            "check the fit in the mirror"
        ],
        expectedObjectCategories: ["counter", "uprightObject", "container", "uprightObject"]
    )

    static let stationTicketing = ScenarioCard(
        id: "station_ticketing",
        setting: "Train station ticket counter",
        learnerRole: "traveler buying a ticket",
        sceneGoal: "Find your platform and buy a ticket",
        localContext: "An upright route-map board and a ticket machine sit on the counter; an attendant marker stands nearby.",
        targetInteractions: [
            "find your destination on the route map",
            "ask the attendant which platform you need",
            "walk to the ticket machine",
            "buy a ticket at the machine",
            "go to your platform"
        ],
        expectedObjectCategories: ["counter", "menu", "uprightObject", "npc_marker"]
    )

    static let shrinePurification = ScenarioCard(
        id: "shrine_purification",
        setting: "Shinto shrine purification area",
        learnerRole: "visitor performing the purification ritual",
        sceneGoal: "Purify your hands, make an offering, and choose an amulet",
        localContext: "A low stone surface holds a water basin with a ladle, a donation box, and a small tray of amulets; a priest marker stands nearby.",
        targetInteractions: [
            "bow at the torii gate",
            "take the ladle and rinse your hands",
            "rinse your mouth",
            "replace the ladle on the basin",
            "place a coin in the donation box",
            "bow and clap to pray",
            "receive an amulet from the priest"
        ],
        expectedObjectCategories: ["counter", "container", "smallObject", "container", "smallObject", "npc_marker"]
    )

    static let benchmarkScenarios: [ScenarioCard] = [
        convenienceStore,
        marketStand,
        cafeArrivalSeating,
        cafeOrdering,
        cafePayingCheck,
        clothingBrowseCompare,
        clothingTryingOn,
        stationTicketing,
        shrinePurification
    ]

    static func fallbackRawPlan(for scenario: ScenarioCard) -> InteractionWorldPlan {
        switch scenario.id {
        case convenienceStore.id:
            return convenienceStoreRawPlan
        case marketStand.id:
            return marketStandRawPlan
        default:
            return genericRawPlan(for: scenario)
        }
    }

    private static func genericRawPlan(for scenario: ScenarioCard) -> InteractionWorldPlan {
        let categories = scenario.expectedObjectCategories ?? []
        let surfaceObject = WorldObjectSpec(
            id: "interaction_surface",
            displayName: surfaceDisplayName(for: categories),
            description: "Stable support surface for the scene",
            kind: .counter,
            position: [0, 0.62, -0.92],
            size: [1.10, 0.10, 0.56],
            color: .brown,
            isInteractive: false
        )

        var objects: [WorldObjectSpec] = [surfaceObject]
        for category in categories where !isSurfaceCategory(category) {
            let spec = objectSpec(for: category, index: objects.count)
            if !objects.contains(where: { $0.id == spec.id }) {
                objects.append(spec)
            }
        }

        if !objects.contains(where: { $0.kind == .npcMarker }) {
            objects.append(objectSpec(for: "npc_marker", index: objects.count))
        }

        let taskObjects = objects.filter { $0.id != surfaceObject.id }
        let tasks = scenario.targetInteractions.enumerated().map { index, instruction in
            task(for: instruction, index: index, objects: taskObjects, surfaceId: surfaceObject.id)
        }

        return InteractionWorldPlan(
            id: "\(scenario.id)_preset_raw",
            scenario: scenario,
            objects: objects,
            tasks: tasks
        )
    }

    private static func objectSpec(for category: String, index: Int) -> WorldObjectSpec {
        let id = normalizedId(category)
        let position = SIMD3<Float>(
            -0.46 + Float(index % 4) * 0.30,
            0.78 + Float(index / 4) * 0.10,
            -0.72 - Float(index / 4) * 0.20
        )

        if id.contains("card_reader") || id.contains("payment") || id.contains("terminal") || id.contains("tablet") || id.contains("kiosk") {
            return WorldObjectSpec(
                id: id.contains("card_reader") ? "card_reader" : id,
                displayName: title(from: id),
                description: "Tap or indicate this payment/check-in device",
                kind: .cardReader,
                position: position,
                size: [0.22, 0.06, 0.16],
                color: .green,
                isInteractive: true
            )
        }

        if id.contains("menu") || id.contains("sign") || id.contains("map") {
            return WorldObjectSpec(
                id: id,
                displayName: title(from: id),
                description: "Upright context object for pointing or indicating",
                kind: .menu,
                position: position,
                size: [0.38, 0.44, 0.05],
                color: .cyan,
                isInteractive: true
            )
        }

        if id.contains("marker") || id.contains("cashier") || id.contains("vendor") || id.contains("receptionist") || id.contains("clerk") || id.contains("attendant") || id.contains("pharmacist") {
            return WorldObjectSpec(
                id: id == "npc_marker" ? "staff_marker" : id,
                displayName: title(from: id == "npc_marker" ? "staff_marker" : id),
                description: "Person marker for gesture interactions",
                kind: .npcMarker,
                position: [0, 1.02, -1.38],
                size: [0.14, 0.34, 0.14],
                color: .purple,
                isInteractive: true
            )
        }

        if id.contains("cup") || id.contains("glass") {
            return WorldObjectSpec(
                id: id,
                displayName: title(from: id),
                description: "Drink container",
                kind: .cup,
                position: position,
                size: [0.14, 0.18, 0.14],
                color: .blue,
                isInteractive: true
            )
        }

        if id.contains("tray") || id.contains("plate") {
            return WorldObjectSpec(
                id: id,
                displayName: title(from: id),
                description: "Shallow tabletop target",
                kind: .tray,
                position: position,
                size: [0.36, 0.05, 0.26],
                color: .gray,
                isInteractive: true
            )
        }

        if id.contains("basket") || id.contains("bag") || id.contains("box") {
            return WorldObjectSpec(
                id: id,
                displayName: title(from: id),
                description: "Container for place interactions",
                kind: .generic(category: "container"),
                position: position,
                size: [0.32, 0.24, 0.24],
                color: .yellow,
                isInteractive: true
            )
        }

        return WorldObjectSpec(
            id: id,
            displayName: title(from: id),
            description: "Task-relevant small object",
            kind: .generic(category: "smallObject"),
            position: position,
            size: [0.18, 0.14, 0.16],
            color: color(for: id),
            isInteractive: true
        )
    }

    private static func task(
        for instruction: String,
        index: Int,
        objects: [WorldObjectSpec],
        surfaceId: String
    ) -> InteractionTask {
        let text = instruction.lowercased()
        let primary = preferredObjectId(for: text, objects: objects) ?? objects.first?.id ?? surfaceId

        if text.contains("wave") {
            let target = objects.first(where: { $0.kind == .npcMarker })?.id
            return InteractionTask(
                id: "preset_task_\(index)",
                instruction: instruction,
                requiredObjectIds: target.map { [$0] } ?? [],
                expectedInteraction: .gesture(.wave, targetId: target)
            )
        }

        if text.contains("place") || text.contains("put") {
            let target = placementTargetId(for: text, objects: objects) ?? surfaceId
            return InteractionTask(
                id: "preset_task_\(index)",
                instruction: instruction,
                requiredObjectIds: primary == target ? [primary] : [primary, target],
                expectedInteraction: .place(objectId: primary, targetId: target)
            )
        }

        if text.contains("indicate") || text.contains("point") || text.contains("show") {
            return InteractionTask(
                id: "preset_task_\(index)",
                instruction: instruction,
                requiredObjectIds: [primary],
                expectedInteraction: .indicate(objectId: primary)
            )
        }

        return InteractionTask(
            id: "preset_task_\(index)",
            instruction: instruction,
            requiredObjectIds: [primary],
            expectedInteraction: .tap(objectId: primary)
        )
    }

    private static func preferredObjectId(for text: String, objects: [WorldObjectSpec]) -> String? {
        if text.contains("pay") || text.contains("tap") || text.contains("terminal") || text.contains("reader") || text.contains("kiosk") || text.contains("tablet") {
            return objects.first(where: { $0.kind == .cardReader })?.id
        }
        if text.contains("wave") {
            return objects.first(where: { $0.kind == .npcMarker })?.id
        }
        if text.contains("menu") || text.contains("sign") || text.contains("map") {
            return objects.first(where: { $0.kind == .menu })?.id
        }
        return objects.first(where: { object in
            let haystack = "\(object.id) \(object.displayName)".lowercased()
            return text.components(separatedBy: " ").contains { token in
                token.count > 3 && haystack.contains(token)
            }
        })?.id ?? objects.first?.id
    }

    private static func placementTargetId(for text: String, objects: [WorldObjectSpec]) -> String? {
        if text.contains("bag") || text.contains("basket") || text.contains("box") {
            return objects.first(where: { object in
                object.id.contains("bag") || object.id.contains("basket") || object.id.contains("box")
            })?.id
        }
        if text.contains("tray") || text.contains("plate") {
            return objects.first(where: { object in
                object.id.contains("tray") || object.id.contains("plate")
            })?.id
        }
        return nil
    }

    private static func isSurfaceCategory(_ category: String) -> Bool {
        let id = normalizedId(category)
        return ["counter", "table", "desk", "stand", "stall", "surface"].contains { id.contains($0) }
    }

    private static func surfaceDisplayName(for categories: [String]) -> String {
        if let category = categories.first(where: isSurfaceCategory) {
            return title(from: normalizedId(category))
        }
        return "Interaction Surface"
    }

    private static func normalizedId(_ value: String) -> String {
        let tokens = value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
        return tokens.joined(separator: "_").isEmpty ? "object" : tokens.joined(separator: "_")
    }

    private static func title(from id: String) -> String {
        id.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func color(for id: String) -> WorldObjectColor {
        if id.contains("apple") || id.contains("shirt") {
            return .red
        }
        if id.contains("ticket") || id.contains("card") || id.contains("paper") {
            return .yellow
        }
        if id.contains("wallet") || id.contains("passport") {
            return .brown
        }
        return .blue
    }
}

struct InteractionWorldTestView: View {
    @EnvironmentObject private var runtime: InteractionWorldRuntime
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @StateObject private var generator = InteractionWorldGenerator()
    @State private var isImmersiveOpen = false
    @State private var openError: String?
    @State private var metricInfoPopover: ManualEvaluationMetric?
    @State private var isGenerating = false
    @State private var isBatchGenerating = false
    @State private var batchGenerationStatus: String?
    @State private var generationResult: GenerationResult?
    @State private var generationError: String?
    @State private var generationLogURL: URL?
    @State private var sam3DBaseURL = "http://127.0.0.1:8010"
    @State private var isRealizingSAM3D = false
    @State private var sam3DStatus: String?
    @State private var sam3DResult: SAM3DSceneRealizationResult?
    @State private var savedScenes: [SavedInteractionWorldScene] = []
    @State private var selectedSavedSceneID: String?
    @State private var savedSceneStatus: String?
    @State private var scenarioRunnerMode: ScenarioRunnerMode = .cafeBaseline
    @State private var editableSetting = "Japanese convenience store"
    @State private var editableLearnerRole = "customer"
    @State private var editableSceneGoal = "Buy a snack and pay at the register"
    @State private var editableLocalContext = "The learner is standing near a counter with snacks, a basket, a wallet, and a payment terminal in reach."
    @State private var editableTargetInteractions = """
    pick up a snack
    place the snack in the basket
    indicate the payment terminal
    tap the payment terminal
    wave goodbye to the cashier
    """
    @State private var editableExpectedObjectCategories = """
    counter
    snack
    basket
    wallet
    card_reader
    npc_marker
    """

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 360)

            Divider()
                .overlay(Color.white.opacity(0.18))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    scenarioRunnerCard
                    sam3DBridgeCard
                    savedScenesCard
                    controls
                    evaluationCard
                    manualEvaluationPanel
                }
                .padding(22)
            }
            .frame(minWidth: 500)

            Divider()
                .overlay(Color.white.opacity(0.18))

            eventLog
                .frame(width: 300)
        }
        .foregroundStyle(.white)
        .background(windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .popover(item: $metricInfoPopover) { metric in
            VStack(alignment: .leading, spacing: 10) {
                Text(metric.title)
                    .font(.headline)
                Text(metric.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 320)
        }
        .onDisappear {
            Task {
                if isImmersiveOpen {
                    await dismissImmersiveSpace()
                }
            }
        }
        .onAppear {
            refreshSavedScenes()
        }
    }

    private var windowBackground: Color {
        Color(red: 0.07, green: 0.075, blue: 0.085).opacity(0.96)
    }

    private var cardBackground: Color {
        Color(red: 0.14, green: 0.15, blue: 0.16).opacity(0.92)
    }

    private var activeRowBackground: Color {
        Color(red: 0.12, green: 0.22, blue: 0.36).opacity(0.86)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            currentTaskCard
            ScrollView {
                taskList
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color(red: 0.09, green: 0.095, blue: 0.105).opacity(0.94))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Interaction World")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(runtime.plan.scenario.setting)
                .font(.headline)
            Text(runtime.plan.scenario.sceneGoal)
                .foregroundStyle(.secondary)
            Text(runtime.plan.scenario.localContext)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scenarioRunnerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scenario Runner")
                        .font(.headline)
                    Text("Generate a primitive interactive world from a ScenarioCard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Scenario", selection: $scenarioRunnerMode) {
                    ForEach(ScenarioRunnerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)
            }

            if scenarioRunnerMode == .editable {
                editableScenarioFields
            } else {
                selectedScenarioSummary
            }

            HStack(spacing: 10) {
                Button {
                    Task { await generateSelectedPlan() }
                } label: {
                    Label(
                        isGenerating ? "Generating..." : "Generate Plan",
                        systemImage: "sparkles"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)

                Button {
                    runtime.load(CafeCounterDemoPlan.plan)
                    generationResult = nil
                    generationError = nil
                    generationLogURL = nil
                    sam3DResult = nil
                    sam3DStatus = nil
                } label: {
                    Label("Load Baseline", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)
            }

            Button {
                loadSelectedLayoutDemo()
            } label: {
                Label("Load Layout Demo", systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating)

            generationStatus
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var sam3DBridgeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SAM 3D Bridge")
                        .font(.headline)
                    Text("Generate a plan from the scenario, normalize its layout, send it to the SAM 3D service, then load generated object previews plus SAM3D assets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("SAM 3D service URL", text: $sam3DBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button {
                    sam3DBaseURL = "http://127.0.0.1:8010"
                } label: {
                    Label("Local", systemImage: "link")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            }

            Button {
                Task { await generateSelectedSceneWithSAM3D() }
            } label: {
                Label(
                    isGenerating || isRealizingSAM3D ? "Generating..." : "Generate Scene + SAM3D Objects",
                    systemImage: "sparkles.rectangle.stack"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || isRealizingSAM3D)

            HStack(spacing: 10) {
                Button {
                    Task { await generateAllBenchmarkPlans() }
                } label: {
                    Label(
                        isBatchGenerating ? "Batch running..." : "Generate All Plans",
                        systemImage: "square.stack.3d.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating || isRealizingSAM3D || isBatchGenerating)

                Button {
                    Task { await generateAllBenchmarkScenesWithSAM3D() }
                } label: {
                    Label(
                        isBatchGenerating ? "Batch running..." : "Generate All + SAM3D",
                        systemImage: "sparkles.rectangle.stack"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating || isRealizingSAM3D || isBatchGenerating)
            }

            Button {
                Task { await generateAllBenchmarkScenesWithSAM3D(forceRegenerate: true) }
            } label: {
                Label(
                    isBatchGenerating ? "Batch running..." : "Regenerate All + SAM3D",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating || isRealizingSAM3D || isBatchGenerating)

            if let batchGenerationStatus {
                Text(batchGenerationStatus)
                    .font(.caption)
                    .foregroundStyle(batchGenerationStatus.hasPrefix("Batch failed") ? .red : .secondary)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await realizeCurrentPlanWithSAM3D() }
                } label: {
                    Label(
                        isRealizingSAM3D ? "Realizing..." : "Realize Current Plan",
                        systemImage: "sparkles.rectangle.stack"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRealizingSAM3D)

                Button {
                    sam3DResult = nil
                    sam3DStatus = nil
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isRealizingSAM3D)
            }

            Button {
                Task { await loadSAM3DLayoutPlan() }
            } label: {
                Label("Load SAM3D Layout Plan", systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRealizingSAM3D)

            if let sam3DStatus {
                Text(sam3DStatus)
                    .font(.caption)
                    .foregroundStyle(sam3DStatus.hasPrefix("SAM 3D failed") ? .red : .secondary)
            }

            if let sam3DResult {
                VStack(alignment: .leading, spacing: 6) {
                    metricRow("Realized objects", "\(sam3DResult.realizedCount)/\(runtime.plan.objects.count)")
                    metricRow("Failed/missing", "\(sam3DResult.failedCount)")
                    metricRow("Cached assets", "\(sam3DResult.cachedAssets.count)")

                    if let imageURL = sam3DResult.response.generatedImageURL {
                        Text("Generated image: \(imageURL.absoluteString)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    ForEach(sam3DResult.response.objects.prefix(6)) { object in
                        HStack {
                            Text(object.objectId)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(object.status.rawValue)
                                .font(.caption2)
                                .foregroundStyle(object.status == .realized ? .green : .yellow)
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var savedScenesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Scenes")
                        .font(.headline)
                    Text("Reload generated scenes for evaluation without rerunning LLM or SAM 3D generation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refreshSavedScenes()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            }

            if savedScenes.isEmpty {
                Text("No saved generated scenes yet. Finished generations are saved automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Saved scene", selection: Binding(
                    get: { selectedSavedSceneID ?? savedScenes.first?.id ?? "" },
                    set: { selectedSavedSceneID = $0 }
                )) {
                    ForEach(savedScenes) { scene in
                        Text(savedScenePickerTitle(scene)).tag(scene.id)
                    }
                }
                .pickerStyle(.menu)

                if let scene = selectedSavedScene() {
                    VStack(alignment: .leading, spacing: 4) {
                        metricRow("Scenario", scene.scenarioTitle)
                        metricRow("Objects", "\(scene.realizedObjectCount)/\(scene.objectCount) SAM3D realized")
                        metricRow("Saved", scene.exportedAt.formatted(date: .abbreviated, time: .shortened))
                        Text(scene.fileName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .padding(10)
                    .background(Color.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    loadSelectedSavedScene()
                } label: {
                    Label("Load Saved Scene", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if let savedSceneStatus {
                Text(savedSceneStatus)
                    .font(.caption)
                    .foregroundStyle(savedSceneStatus.hasPrefix("Failed") ? .red : .secondary)
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var selectedScenarioSummary: some View {
        let scenario = selectedScenario() ?? CafeCounterDemoPlan.scenario
        return VStack(alignment: .leading, spacing: 6) {
            Text(scenario.setting)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(scenario.sceneGoal)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(scenario.targetInteractions.joined(separator: " • "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var editableScenarioFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Setting", text: $editableSetting)
                .textFieldStyle(.roundedBorder)
            TextField("Learner role", text: $editableLearnerRole)
                .textFieldStyle(.roundedBorder)
            TextField("Scene goal", text: $editableSceneGoal)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Local context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $editableLocalContext)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target interactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editableTargetInteractions)
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Expected object categories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editableExpectedObjectCategories)
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await toggleImmersive() }
            } label: {
                Label(
                    isImmersiveOpen ? "Close Micro-world" : "Open Micro-world",
                    systemImage: isImmersiveOpen ? "xmark.circle.fill" : "cube.transparent.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Button {
                    runtime.process(.gesture(.wave, targetId: currentGestureTarget(for: .wave)))
                } label: {
                    Label("Mock Wave", systemImage: "hand.wave")
                }
                .buttonStyle(.bordered)

                Button {
                    runtime.process(.gesture(.point, targetId: currentGestureTarget(for: .point)))
                } label: {
                    Label("Mock Point", systemImage: "hand.point.up.left")
                }
                .buttonStyle(.bordered)

                Button {
                    runtime.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            Button {
                Task { await generateCafePlan() }
            } label: {
                Label(
                    isGenerating ? "Generating..." : "Generate Cafe Plan",
                    systemImage: "sparkles"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating)

            if let openError {
                Text(openError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var generationStatus: some View {
        if let generationError {
            Text(generationError)
                .font(.caption)
                .foregroundStyle(.red)
        }

        if let generationResult {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(generationResult.succeeded ? "Generated plan loaded." : "Generation failed.")
                        .font(.caption)
                        .foregroundStyle(generationResult.succeeded ? .green : .yellow)
                    Spacer()
                    Text(String(format: "%.1fs", generationResult.totalGenerationTimeSeconds))
                        .font(.caption)
                        .monospacedDigit()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    generationStageRow("Step 1 objects", generationStageStatus(generationResult, stage: .objects))
                    generationStageRow("Step 3 tasks", generationStageStatus(generationResult, stage: .tasks))
                    generationStageRow("Step 4 validation", generationStageStatus(generationResult, stage: .validation))
                    metricRow("Attempts", "\(generationResult.attempts.count)")
                    if let layoutSummary = generationResult.layoutSummary {
                        metricRow("Layout", "\(layoutSummary.strategy) • \(layoutSummary.objectCount) objects")
                        metricRow("Relations", "\(layoutSummary.relationCount)")
                        if let insertedSurfaceId = layoutSummary.insertedSurfaceId {
                            metricRow("Added surface", insertedSurfaceId)
                        }
                        layoutReasoningSummary(layoutSummary)
                    }
                }
                .font(.caption2)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(generationResult.attempts, id: \.attemptNumber) { attempt in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Attempt \(attempt.attemptNumber) • \(attempt.stage.title) • \(String(format: "%.1fs", attempt.durationSeconds))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(attempt.outcome.shortDescription)
                                .font(.caption2)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                if let generationLogURL {
                    Text("Exported log: \(generationLogURL.lastPathComponent)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    exportCurrentGenerationLog()
                } label: {
                    Label("Export Evaluation Log", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)
            }
            .padding(12)
            .background(Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func generationStageRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(stageStatusColor(value))
        }
    }

    private func generationStageStatus(
        _ result: GenerationResult,
        stage: GenerationPipelineDisplayStage
    ) -> String {
        switch stage {
        case .objects:
            if result.succeeded || result.attempts.contains(where: { $0.stage == .taskGeneration || $0.stage == .validation || $0.stage == .fullPipeline }) {
                return "passed"
            }
            return result.attempts.last?.stage == .objectGeneration ? "failed" : "not reached"
        case .tasks:
            if result.succeeded || result.attempts.contains(where: { $0.stage == .validation || $0.stage == .fullPipeline }) {
                return "passed"
            }
            return result.attempts.last?.stage == .taskGeneration ? "failed" : "not reached"
        case .validation:
            if result.succeeded {
                return "passed"
            }
            return result.attempts.last?.stage == .validation ? "failed" : "not reached"
        }
    }

    private func stageStatusColor(_ value: String) -> Color {
        switch value {
        case "passed":
            return .green
        case "failed":
            return .yellow
        default:
            return .secondary
        }
    }

    private func layoutReasoningSummary(_ summary: InteractionWorldLayoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Layout Reasoning")
                .font(.caption)
                .fontWeight(.semibold)

            ForEach(summary.relations.prefix(5)) { relation in
                Text(relationDescription(relation))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()
                .background(Color.white.opacity(0.16))

            ForEach(summary.objectSummaries.prefix(6), id: \.objectId) { object in
                HStack(spacing: 8) {
                    Text(object.objectId)
                        .font(.caption2)
                        .fontWeight(.semibold)
                    Text(object.role)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text(vectorDescription(object.finalPosition))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func relationDescription(_ relation: InteractionWorldSpatialRelation) -> String {
        "\(relation.subjectId) \(relation.kind.displayName) \(relation.objectId)"
    }

    private func vectorDescription(_ vector: SIMD3<Float>) -> String {
        String(format: "(%.2f, %.2f, %.2f)", vector.x, vector.y, vector.z)
    }

    private var currentTaskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current Task")
                    .font(.headline)
                Spacer()
                Text(runtime.progressText)
                    .font(.headline)
                    .monospacedDigit()
            }

            if let task = runtime.currentTask {
                Text(task.instruction)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(task.expectedInteraction.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("All tasks complete.")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task Queue")
                .font(.headline)

            ForEach(Array(runtime.plan.tasks.enumerated()), id: \.element.id) { index, task in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: taskIcon(index: index, taskId: task.id))
                        .foregroundStyle(taskColor(index: index, taskId: task.id))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.instruction)
                            .fontWeight(index == runtime.currentTaskIndex ? .semibold : .regular)
                        Text(task.requiredObjectIds.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
                .background(index == runtime.currentTaskIndex ? activeRowBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var evaluationCard: some View {
        let result = runtime.evaluate()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Evaluation")
                .font(.headline)
            metricRow("Object coverage", result.objectCoverageSummary)
            metricRow("Handler coverage", result.handlerCoverageSummary)
            metricRow("Completed tasks", result.completionSummary)
            if let failed = result.firstFailedTaskId {
                metricRow("First incomplete", failed)
            } else {
                metricRow("First incomplete", "none")
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var manualEvaluationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manual Evaluation")
                        .font(.headline)
                    Text("Score generated objects, wiring, and runtime behavior after testing the scene.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(runtime.manualEvaluationSummary)
                    .font(.headline)
                    .monospacedDigit()
            }

            scenarioManualRatings
            objectManualRatings

            ForEach(runtime.plan.tasks) { task in
                manualTaskCard(task)
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var scenarioManualRatings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scenario")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                Text("Spatial layout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Spatial layout", selection: scenarioLayoutBinding) {
                    ForEach(ScenarioLayoutRating.allCases) { rating in
                        Text(rating.title).tag(rating)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            HStack {
                Text("Scenario fidelity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Scenario fidelity", selection: scenarioFidelityBinding) {
                    ForEach(ScenarioFidelityRating.allCases) { rating in
                        Text(rating.title).tag(rating)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var objectManualRatings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generated Objects")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(runtime.plan.objects) { object in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(object.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(object.id)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let visualAsset = object.visualAsset {
                            Label(
                                "\(visualAsset.source.rawValue) \(visualAsset.format.rawValue)",
                                systemImage: visualAsset.status == .realized ? "sparkles" : "cube.transparent"
                            )
                            .font(.caption2)
                            .foregroundStyle(visualAsset.status == .realized ? .cyan : .secondary)
                            .lineLimit(1)
                        }
                    }
                    Spacer()
                    Picker(
                        object.displayName,
                        selection: generatedObjectRatingBinding(objectId: object.id)
                    ) {
                        ForEach(GeneratedObjectRating.allCases) { rating in
                            Text(rating.title).tag(rating)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func manualTaskCard(_ task: InteractionTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.instruction)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(task.expectedInteraction.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Primitive faithfulness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(
                    "Primitive faithfulness",
                    selection: generatedTaskRatingBinding(taskId: task.id)
                ) {
                    ForEach(GeneratedTaskFidelityRating.allCases) { rating in
                        Text(rating.title).tag(rating)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            ForEach(ManualEvaluationMetric.allCases) { metric in
                manualMetricRow(task: task, metric: metric)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func manualMetricRow(
        task: InteractionTask,
        metric: ManualEvaluationMetric
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                metricInfoPopover = metric
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(metric.description)

            Text(metric.title)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker(metric.title, selection: manualRatingBinding(taskId: task.id, metric: metric)) {
                ForEach(ManualEvaluationRating.allCases) { rating in
                    Text(rating.title).tag(rating)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 116)
            .tint(ratingColor(runtime.manualRating(taskId: task.id, metric: metric)))
        }
    }

    private func manualRatingBinding(
        taskId: String,
        metric: ManualEvaluationMetric
    ) -> Binding<ManualEvaluationRating> {
        Binding {
            runtime.manualRating(taskId: taskId, metric: metric)
        } set: { newValue in
            runtime.setManualRating(newValue, taskId: taskId, metric: metric)
        }
    }

    private var scenarioLayoutBinding: Binding<ScenarioLayoutRating> {
        Binding {
            runtime.scenarioLayoutRating
        } set: { newValue in
            runtime.setScenarioLayoutRating(newValue)
        }
    }

    private var scenarioFidelityBinding: Binding<ScenarioFidelityRating> {
        Binding {
            runtime.scenarioFidelityRating
        } set: { newValue in
            runtime.setScenarioFidelityRating(newValue)
        }
    }

    private func generatedTaskRatingBinding(taskId: String) -> Binding<GeneratedTaskFidelityRating> {
        Binding {
            runtime.generatedTaskRating(taskId: taskId)
        } set: { newValue in
            runtime.setGeneratedTaskRating(newValue, taskId: taskId)
        }
    }

    private func generatedObjectRatingBinding(objectId: String) -> Binding<GeneratedObjectRating> {
        Binding {
            runtime.generatedObjectRating(objectId: objectId)
        } set: { newValue in
            runtime.setGeneratedObjectRating(newValue, objectId: objectId)
        }
    }

    private func ratingColor(_ rating: ManualEvaluationRating) -> Color {
        switch rating {
        case .yes:
            return .green
        case .partial:
            return .yellow
        case .no:
            return .red
        case .unscored:
            return .secondary
        }
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Event Log")
                .font(.headline)

            if runtime.eventLog.isEmpty {
                Text("No events yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(runtime.eventLog) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(
                                    entry.matched ? "matched" : "ignored",
                                    systemImage: entry.matched ? "checkmark.circle.fill" : "minus.circle"
                                )
                                .font(.caption)
                                .foregroundStyle(entry.matched ? .green : .secondary)
                                Text(entry.eventDescription)
                                    .font(.subheadline)
                                Text(entry.taskId)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(red: 0.09, green: 0.095, blue: 0.105).opacity(0.94))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func taskIcon(index: Int, taskId: String) -> String {
        if runtime.completedTaskIds.contains(taskId) {
            return "checkmark.circle.fill"
        }
        if index == runtime.currentTaskIndex {
            return "circle.inset.filled"
        }
        return "circle"
    }

    private func taskColor(index: Int, taskId: String) -> Color {
        if runtime.completedTaskIds.contains(taskId) {
            return .green
        }
        if index == runtime.currentTaskIndex {
            return .blue
        }
        return .secondary
    }

    private func currentGestureTarget(for gesture: GestureKind) -> String? {
        guard case .gesture(let expectedGesture, let targetId) = runtime.currentTask?.expectedInteraction,
              expectedGesture == gesture else {
            return nil
        }

        return targetId
    }

    private func selectedScenario() -> ScenarioCard? {
        switch scenarioRunnerMode {
        case .cafeBaseline:
            return CafeCounterDemoPlan.scenario
        case .convenienceStore:
            return PrototypeScenarioCards.convenienceStore
        case .marketStand:
            return PrototypeScenarioCards.marketStand
        case .cafeArrivalSeating:
            return PrototypeScenarioCards.cafeArrivalSeating
        case .cafeOrdering:
            return PrototypeScenarioCards.cafeOrdering
        case .cafePayingCheck:
            return PrototypeScenarioCards.cafePayingCheck
        case .clothingBrowseCompare:
            return PrototypeScenarioCards.clothingBrowseCompare
        case .clothingTryingOn:
            return PrototypeScenarioCards.clothingTryingOn
        case .stationTicketing:
            return PrototypeScenarioCards.stationTicketing
        case .shrinePurification:
            return PrototypeScenarioCards.shrinePurification
        case .editable:
            let targetInteractions = parsedList(from: editableTargetInteractions)
            guard !targetInteractions.isEmpty else { return nil }

            let categories = parsedList(from: editableExpectedObjectCategories)
            let setting = editableSetting.trimmedNonEmpty ?? "Editable scenario"

            return ScenarioCard(
                id: "editable_\(slug(setting))",
                setting: setting,
                learnerRole: editableLearnerRole.trimmedNonEmpty ?? "learner",
                sceneGoal: editableSceneGoal.trimmedNonEmpty ?? "Complete the practice interaction",
                localContext: editableLocalContext.trimmedNonEmpty ?? "The learner is standing near the relevant objects.",
                targetInteractions: targetInteractions,
                expectedObjectCategories: categories.isEmpty ? nil : categories
            )
        }
    }

    private func parsedList(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func slug(_ text: String) -> String {
        let tokens = text
            .lowercased()
            .split { character in
                !character.isLetter && !character.isNumber
            }
            .prefix(6)

        let value = tokens.joined(separator: "_")
        return value.isEmpty ? "scenario" : value
    }

    private func toggleImmersive() async {
        if isImmersiveOpen {
            await dismissImmersiveSpace()
            isImmersiveOpen = false
            return
        }

        let result = await openImmersiveSpace(id: "interactionWorldImmersive")
        switch result {
        case .opened:
            isImmersiveOpen = true
            openError = nil
        case .error:
            openError = "Could not open the interaction world immersive space."
        case .userCancelled:
            openError = "Opening the immersive space was cancelled."
        @unknown default:
            openError = "Unknown immersive space result."
        }
    }

    private func generateCafePlan() async {
        await generatePlan(for: CafeCounterDemoPlan.scenario)
    }

    private func generateSelectedPlan() async {
        guard let scenario = selectedScenario() else {
            generationResult = nil
            generationLogURL = nil
            generationError = "Add at least one target interaction before generating."
            return
        }

        await generatePlan(for: scenario)
    }

    private func generateSelectedSceneWithSAM3D() async {
        guard let scenario = selectedScenario() else {
            generationResult = nil
            generationLogURL = nil
            generationError = "Add at least one target interaction before generating."
            return
        }

        await generateSceneWithSAM3D(for: scenario)
    }

    private func generateAllBenchmarkPlans() async {
        isBatchGenerating = true
        isGenerating = true
        generationError = nil
        sam3DStatus = nil
        sam3DResult = nil

        var savedCount = 0
        var skippedCount = 0
        let scenarios = PrototypeScenarioCards.benchmarkScenarios

        for (index, scenario) in scenarios.enumerated() {
            if hasSavedScene(for: scenario.id) {
                skippedCount += 1
                batchGenerationStatus = "Skipping saved plan \(index + 1)/\(scenarios.count): \(scenario.setting)"
                continue
            }

            batchGenerationStatus = "Generating plan \(index + 1)/\(scenarios.count): \(scenario.setting)"

            do {
                let result = try await generator.generatePlan(for: scenario)
                generationResult = result
                if let plan = result.plan {
                    runtime.load(plan)
                }
                generationLogURL = try writeGenerationRunLog(result)
                savedCount += 1
                refreshSavedScenes()
            } catch {
                generationError = "Batch plan generation failed for \(scenario.id): \(error.localizedDescription)"
            }
        }

        batchGenerationStatus = "Saved \(savedCount), skipped \(skippedCount), checked \(scenarios.count) benchmark plans for L2 evaluation."
        isGenerating = false
        isBatchGenerating = false
    }

    private func generateAllBenchmarkScenesWithSAM3D(forceRegenerate: Bool = false) async {
        guard let baseURL = URL(string: sam3DBaseURL.trimmedNonEmpty ?? "") else {
            batchGenerationStatus = SAM3DSceneRealizationError
                .invalidBaseURL(sam3DBaseURL)
                .localizedDescription
            return
        }

        isBatchGenerating = true
        isGenerating = true
        isRealizingSAM3D = true
        generationError = nil
        sam3DResult = nil

        var savedCount = 0
        var skippedCount = 0
        let scenarios = PrototypeScenarioCards.benchmarkScenarios

        for (index, scenario) in scenarios.enumerated() {
            if !forceRegenerate && hasSavedScene(for: scenario.id, requiringRealizedAssets: true) {
                skippedCount += 1
                batchGenerationStatus = "Skipping saved SAM3D scene \(index + 1)/\(scenarios.count): \(scenario.setting)"
                continue
            }

            batchGenerationStatus = "Generating SAM3D scene \(index + 1)/\(scenarios.count): \(scenario.setting)"
            sam3DStatus = "Generating plan for \(scenario.setting)..."

            do {
                let generatedResult = try await generator.generatePlan(for: scenario)
                generationResult = generatedResult

                guard let plan = generatedResult.plan else {
                    generationError = "Batch generated no plan for \(scenario.id)."
                    continue
                }

                runtime.load(plan)
                generationLogURL = try writeGenerationRunLog(generatedResult)
                refreshSavedScenes()
                sam3DStatus = "SAM 3D is realizing \(scenario.setting)..."

                let client = SAM3DSceneRealizationClient(baseURL: baseURL)
                client.progressHandler = { message in
                    Task { @MainActor in
                        sam3DStatus = message
                    }
                }

                let realization = try await client.realize(plan: plan)
                sam3DResult = realization
                runtime.load(realization.reconciledPlan)

                let result = GenerationResult(
                    scenario: generatedResult.scenario,
                    plan: realization.reconciledPlan,
                    attempts: generatedResult.attempts,
                    totalGenerationTimeSeconds: generatedResult.totalGenerationTimeSeconds,
                    layoutSummary: generatedResult.layoutSummary
                )
                generationResult = result
                generationLogURL = try writeGenerationRunLog(result)
                savedCount += 1
                refreshSavedScenes()
                sam3DStatus = "Saved SAM3D scene \(index + 1)/\(scenarios.count): \(scenario.setting)"
            } catch {
                generationError = "Batch SAM3D generation failed for \(scenario.id): \(error.localizedDescription)"
                sam3DStatus = "SAM 3D failed for \(scenario.setting): \(error.localizedDescription)"
            }
        }

        batchGenerationStatus = "Saved \(savedCount), skipped \(skippedCount), checked \(scenarios.count) benchmark SAM3D scenes."
        isGenerating = false
        isRealizingSAM3D = false
        isBatchGenerating = false
    }

    private func loadSelectedLayoutDemo() {
        let rawPlan = selectedLayoutDemoPlan()
        let layoutResult = InteractionWorldLayoutSolver.solve(rawPlan)
        let result = GenerationResult(
            scenario: rawPlan.scenario,
            plan: layoutResult.plan,
            attempts: [
                GenerationAttempt(
                    attemptNumber: 1,
                    stage: .fullPipeline,
                    durationSeconds: 0,
                    outcome: .success,
                    rawObjectsJSON: nil,
                    rawTasksJSON: nil,
                    validationError: nil
                )
            ],
            totalGenerationTimeSeconds: 0,
            layoutSummary: layoutResult.summary
        )

        generationResult = result
        generationError = nil
        generationLogURL = nil
        sam3DResult = nil
        sam3DStatus = nil
        runtime.load(layoutResult.plan)

            do {
                generationLogURL = try writeGenerationRunLog(result)
                refreshSavedScenes()
            } catch {
                generationError = "Demo loaded, but export failed: \(error.localizedDescription)"
            }
    }

    private func generatePlan(for scenario: ScenarioCard) async {
        isGenerating = true
        generationError = nil
        generationResult = nil
        generationLogURL = nil
        sam3DResult = nil
        sam3DStatus = nil

        do {
            let result = try await generator.generatePlan(for: scenario)
            generationResult = result

            if let plan = result.plan {
                runtime.load(plan)
            }

            do {
                generationLogURL = try writeGenerationRunLog(result)
                refreshSavedScenes()
            } catch {
                generationError = "Generated, but export failed: \(error.localizedDescription)"
            }
        } catch {
            generationError = error.localizedDescription
        }

        isGenerating = false
    }

    private func generateSceneWithSAM3D(for scenario: ScenarioCard) async {
        guard let baseURL = URL(string: sam3DBaseURL.trimmedNonEmpty ?? "") else {
            sam3DStatus = SAM3DSceneRealizationError
                .invalidBaseURL(sam3DBaseURL)
                .localizedDescription
            return
        }

        isGenerating = true
        isRealizingSAM3D = true
        generationError = nil
        generationResult = nil
        generationLogURL = nil
        sam3DResult = nil
        sam3DStatus = "Generating plan, then sending objects to SAM 3D..."

        do {
            let generatedResult = try await generator.generatePlan(for: scenario)

            guard let plan = generatedResult.plan else {
                generationResult = generatedResult
                generationError = "Plan generation failed before SAM 3D realization."
                sam3DStatus = nil
                isGenerating = false
                isRealizingSAM3D = false
                return
            }

            generationResult = generatedResult
            runtime.load(plan)
            sam3DStatus = "Plan loaded. SAM 3D is generating \(plan.objects.count) object assets..."

            let client = SAM3DSceneRealizationClient(baseURL: baseURL)
            client.progressHandler = { message in
                Task { @MainActor in
                    sam3DStatus = message
                }
            }
            let realization = try await client.realize(plan: plan)
            sam3DResult = realization
            runtime.load(realization.reconciledPlan)

            let result = GenerationResult(
                scenario: generatedResult.scenario,
                plan: realization.reconciledPlan,
                attempts: generatedResult.attempts,
                totalGenerationTimeSeconds: generatedResult.totalGenerationTimeSeconds,
                layoutSummary: generatedResult.layoutSummary
            )
            generationResult = result
            sam3DStatus = "Loaded \(realization.realizedCount)/\(plan.objects.count) SAM 3D-generated object assets."

            do {
                generationLogURL = try writeGenerationRunLog(result)
                refreshSavedScenes()
            } catch {
                generationError = "Generated scene, but export failed: \(error.localizedDescription)"
            }
        } catch {
            sam3DStatus = "SAM 3D failed: \(error.localizedDescription)"
        }

        isGenerating = false
        isRealizingSAM3D = false
    }

    private func selectedLayoutDemoPlan() -> InteractionWorldPlan {
        switch scenarioRunnerMode {
        case .cafeBaseline, .editable:
            return CafeCounterDemoPlan.plan
        case .convenienceStore:
            return PrototypeScenarioCards.convenienceStoreRawPlan
        case .marketStand:
            return PrototypeScenarioCards.marketStandRawPlan
        case .cafeArrivalSeating:
            return PrototypeScenarioCards.fallbackRawPlan(for: PrototypeScenarioCards.cafeArrivalSeating)
        case .cafeOrdering:
            return PrototypeScenarioCards.fallbackRawPlan(for: PrototypeScenarioCards.cafeOrdering)
        case .cafePayingCheck:
            return PrototypeScenarioCards.fallbackRawPlan(for: PrototypeScenarioCards.cafePayingCheck)
        case .clothingBrowseCompare:
            return PrototypeScenarioCards.fallbackRawPlan(for: PrototypeScenarioCards.clothingBrowseCompare)
        case .clothingTryingOn:
            return PrototypeScenarioCards.fallbackRawPlan(for: PrototypeScenarioCards.clothingTryingOn)
        case .stationTicketing:
            return PrototypeScenarioCards.fallbackRawPlan(for: PrototypeScenarioCards.stationTicketing)
        case .shrinePurification:
            return PrototypeScenarioCards.fallbackRawPlan(for: PrototypeScenarioCards.shrinePurification)
        }
    }

    private func realizeCurrentPlanWithSAM3D() async {
        guard let baseURL = URL(string: sam3DBaseURL.trimmedNonEmpty ?? "") else {
            sam3DStatus = SAM3DSceneRealizationError
                .invalidBaseURL(sam3DBaseURL)
                .localizedDescription
            return
        }

        isRealizingSAM3D = true
        sam3DResult = nil
        sam3DStatus = "Sending \(runtime.plan.objects.count) planned objects to SAM 3D service..."

        do {
            let client = SAM3DSceneRealizationClient(baseURL: baseURL)
            client.progressHandler = { message in
                Task { @MainActor in
                    sam3DStatus = message
                }
            }
            let result = try await client.realize(plan: runtime.plan)
            sam3DResult = result
            runtime.load(result.reconciledPlan)
            sam3DStatus = "SAM 3D realization loaded with generated assets when conversion succeeded."
            if let generationResult {
                let savedResult = GenerationResult(
                    scenario: generationResult.scenario,
                    plan: result.reconciledPlan,
                    attempts: generationResult.attempts,
                    totalGenerationTimeSeconds: generationResult.totalGenerationTimeSeconds,
                    layoutSummary: generationResult.layoutSummary
                )
                self.generationResult = savedResult
                generationLogURL = try writeGenerationRunLog(savedResult)
                refreshSavedScenes()
            }
        } catch {
            sam3DStatus = "SAM 3D failed: \(error.localizedDescription)"
        }

        isRealizingSAM3D = false
    }

    private func loadSAM3DLayoutPlan() async {
        guard let baseURL = URL(string: sam3DBaseURL.trimmedNonEmpty ?? "") else {
            sam3DStatus = SAM3DSceneRealizationError
                .invalidBaseURL(sam3DBaseURL)
                .localizedDescription
            return
        }

        isRealizingSAM3D = true
        sam3DStatus = "Loading SAM 3D-derived layout plan..."
        sam3DResult = nil

        do {
            let url = baseURL.appendingPathComponent("layout-plan")
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw SAM3DSceneRealizationError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    body: body
                )
            }

            let plan = try JSONDecoder().decode(InteractionWorldPlan.self, from: data)
            try InteractionWorldRuntime.validate(plan)
            runtime.load(plan)
            sam3DStatus = "Loaded SAM 3D-derived layout plan with \(plan.objects.count) proxy objects."
        } catch {
            sam3DStatus = "SAM 3D failed: \(error.localizedDescription)"
        }

        isRealizingSAM3D = false
    }

    private func exportCurrentGenerationLog() {
        guard let generationResult else {
            generationError = "Generate a plan before exporting."
            return
        }

        do {
            generationLogURL = try writeGenerationRunLog(generationResult)
            generationError = nil
            refreshSavedScenes()
        } catch {
            generationError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func refreshSavedScenes() {
        do {
            savedScenes = try InteractionWorldSavedSceneStore.list()
            if selectedSavedSceneID == nil || !savedScenes.contains(where: { $0.id == selectedSavedSceneID }) {
                selectedSavedSceneID = savedScenes.first?.id
            }
            savedSceneStatus = savedScenes.isEmpty ? nil : "Found \(savedScenes.count) saved generated scene\(savedScenes.count == 1 ? "" : "s")."
        } catch {
            savedSceneStatus = "Failed to load saved scenes: \(error.localizedDescription)"
        }
    }

    private func selectedSavedScene() -> SavedInteractionWorldScene? {
        let selectedID = selectedSavedSceneID ?? savedScenes.first?.id
        return savedScenes.first { $0.id == selectedID }
    }

    private func hasSavedScene(
        for scenarioId: String,
        requiringRealizedAssets: Bool = false
    ) -> Bool {
        do {
            let scenes = try InteractionWorldSavedSceneStore.list()
            return scenes.contains { scene in
                scene.scenarioId == scenarioId
                    && (!requiringRealizedAssets || scene.realizedObjectCount > 0)
            }
        } catch {
            return false
        }
    }

    private func savedScenePickerTitle(_ scene: SavedInteractionWorldScene) -> String {
        "\(scene.scenarioTitle) • \(scene.exportedAt.formatted(date: .numeric, time: .shortened))"
    }

    private func loadSelectedSavedScene() {
        guard let scene = selectedSavedScene() else {
            savedSceneStatus = "No saved scene selected."
            return
        }

        do {
            let log = try InteractionWorldSavedSceneStore.load(url: scene.url)
            guard let plan = log.loadedPlan ?? log.generationResult.plan else {
                savedSceneStatus = "Failed to load saved scene: no plan was saved."
                return
            }

            try InteractionWorldRuntime.validate(plan)
            runtime.load(plan)
            generationResult = log.generationResult
            generationError = nil
            generationLogURL = scene.url
            sam3DResult = nil
            sam3DStatus = "Loaded saved scene \(scene.scenarioTitle) for evaluation."
            savedSceneStatus = "Loaded \(scene.scenarioTitle)."
        } catch {
            savedSceneStatus = "Failed to load saved scene: \(error.localizedDescription)"
        }
    }

    private func writeGenerationRunLog(_ result: GenerationResult) throws -> URL {
        let runtimeForLog = runtime.plan.scenario.id == result.scenario.id ? runtime : nil
        let log = InteractionWorldRunLogFactory.make(
            result: result,
            runtime: runtimeForLog
        )

        return try InteractionWorldSavedSceneStore.write(log)
    }
}

struct InteractionWorldImmersiveView: View {
    @EnvironmentObject private var runtime: InteractionWorldRuntime
    @StateObject private var sceneManager = InteractionWorldSceneManager()

    var body: some View {
        RealityView { content in
            sceneManager.configure(plan: runtime.plan)
            content.add(sceneManager.rootEntity)
        } update: { _ in
            sceneManager.configure(plan: runtime.plan)
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    sceneManager.handleSelect(entity: value.entity, runtime: runtime)
                }
        )
        .simultaneousGesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    sceneManager.handleDrag(entity: value.entity, value: value, runtime: runtime)
                }
                .onEnded { value in
                    sceneManager.handleDragEnd(entity: value.entity, runtime: runtime)
                }
        )
    }
}

@MainActor
final class InteractionWorldSceneManager: ObservableObject {
    let rootEntity = Entity()

    private var hasConfigured = false
    private var plan: InteractionWorldPlan?
    private var entitiesById: [String: ModelEntity] = [:]
    private var specsById: [String: WorldObjectSpec] = [:]
    private var dragStartPositions: [String: SIMD3<Float>] = [:]

    func configure(plan: InteractionWorldPlan) {
        guard !hasConfigured || self.plan?.id != plan.id else { return }

        self.plan = plan
        rootEntity.children.removeAll()
        entitiesById = [:]
        specsById = Dictionary(uniqueKeysWithValues: plan.objects.map { ($0.id, $0) })
        dragStartPositions = [:]

        for object in plan.objects {
            let hasGeneratedVisual = hasGeneratedVisual(for: object)
            let entity = makeEntity(for: object)
            rootEntity.addChild(entity)
            entitiesById[object.id] = entity
            addLabel(
                object.displayName,
                to: entity,
                yOffset: object.size.y / 2 + 0.035,
                compact: hasGeneratedVisual
            )
            if let visualAsset = object.visualAsset {
                if isNativeRealityAsset(visualAsset) {
                    addGeneratedModelAsset(visualAsset, to: entity, object: object)
                } else if visualAsset.previewLocalURL != nil {
                    addGeneratedPreviewBillboard(visualAsset, to: entity, objectSize: object.size)
                } else {
                    addVisualAssetBadge(visualAsset, to: entity, objectSize: object.size)
                }
            }
        }

        hasConfigured = true
    }

    func handleSelect(entity: Entity, runtime: InteractionWorldRuntime) {
        let objectId = normalizedObjectId(for: entity)
        guard let objectId else { return }

        if case .gesture(.point, let targetId) = runtime.currentTask?.expectedInteraction,
           targetId == objectId {
            runtime.process(.gesture(.point, targetId: objectId))
        } else {
            runtime.process(.select(objectId: objectId))
        }
    }

    func handleDrag(
        entity: Entity,
        value: EntityTargetValue<DragGesture.Value>,
        runtime: InteractionWorldRuntime
    ) {
        guard let objectId = normalizedObjectId(for: entity),
              let modelEntity = entitiesById[objectId],
              isDraggable(objectId: objectId, runtime: runtime) else { return }

        if dragStartPositions[objectId] == nil {
            dragStartPositions[objectId] = modelEntity.position
            runtime.process(.dragStarted(objectId: objectId))
        }

        guard let start = dragStartPositions[objectId] else { return }

        let translation = value.convert(value.translation3D, from: .local, to: .scene)
        modelEntity.position = [
            start.x + Float(translation.x),
            max(0.05, start.y + Float(translation.y)),
            start.z + Float(translation.z)
        ]
    }

    func handleDragEnd(entity: Entity, runtime: InteractionWorldRuntime) {
        guard let objectId = normalizedObjectId(for: entity),
              let modelEntity = entitiesById[objectId],
              isDraggable(objectId: objectId, runtime: runtime) else { return }

        let targetId = placementTarget(for: modelEntity.position, objectId: objectId, runtime: runtime)

        if let targetId, let target = entitiesById[targetId] {
            let objectHeight = specsById[objectId]?.size.y ?? 0.08
            let targetHeight = specsById[targetId]?.size.y ?? 0.02
            modelEntity.position = [
                target.position.x,
                target.position.y + (targetHeight / 2) + (objectHeight / 2) + 0.01,
                target.position.z
            ]
        }

        runtime.process(.placed(objectId: objectId, targetId: targetId))
        dragStartPositions[objectId] = nil
    }

    private func isDraggable(objectId: String, runtime: InteractionWorldRuntime) -> Bool {
        switch runtime.currentTask?.expectedInteraction {
        case .drag(let expectedObjectId):
            return expectedObjectId == objectId
        case .place(let expectedObjectId, _):
            return expectedObjectId == objectId
        default:
            return false
        }
    }

    private func placementTarget(
        for position: SIMD3<Float>,
        objectId: String,
        runtime: InteractionWorldRuntime
    ) -> String? {
        guard case .place(let expectedObjectId, let targetId) = runtime.currentTask?.expectedInteraction,
              expectedObjectId == objectId,
              let target = entitiesById[targetId] else { return nil }

        let dx = position.x - target.position.x
        let dz = position.z - target.position.z
        let distance = sqrt(dx * dx + dz * dz)
        let targetSize = specsById[targetId]?.size ?? [0.18, 0.08, 0.18]
        let threshold = max(0.18, max(targetSize.x, targetSize.z) * 0.75)
        return distance < threshold ? targetId : nil
    }

    private func makeEntity(for object: WorldObjectSpec) -> ModelEntity {
        let hasGeneratedVisual = hasGeneratedVisual(for: object)
        let entity = ModelEntity(
            mesh: semanticMesh(for: object),
            materials: [material(object.color.uiColor)]
        )
        entity.name = object.id
        entity.position = object.position

        if object.isInteractive {
            entity.generateCollisionShapes(recursive: true)
            entity.components.set(InputTargetComponent())
        }

        if hasGeneratedVisual {
            entity.model = nil
        } else {
            addSemanticDetails(to: entity, for: object)
        }

        return entity
    }

    private func hasGeneratedVisual(for object: WorldObjectSpec) -> Bool {
        object.visualAsset.map {
            isNativeRealityAsset($0) || $0.previewLocalURL != nil
        } ?? false
    }

    private func semanticMesh(for object: WorldObjectSpec) -> MeshResource {
        if isApple(object) {
            return .generateSphere(radius: max(object.size.x, max(object.size.y, object.size.z)) / 2)
        }
        if isCup(object) || isBasket(object) {
            return .generateCylinder(height: object.size.y, radius: max(object.size.x, object.size.z) / 2)
        }
        if isSnackBag(object) {
            return .generateBox(
                width: max(object.size.x, 0.10),
                height: max(object.size.y, 0.11),
                depth: max(object.size.z * 0.32, 0.025)
            )
        }
        if isPersonMarker(object) {
            return .generateCylinder(height: object.size.y, radius: max(object.size.x, object.size.z) / 2)
        }

        switch object.kind {
        case .cup:
            return .generateCylinder(height: object.size.y, radius: object.size.x / 2)
        case .generic(let category):
            return genericMesh(for: category, size: object.size)
        default:
            return .generateBox(width: object.size.x, height: object.size.y, depth: object.size.z)
        }
    }

    private func genericMesh(for category: String, size: SIMD3<Float>) -> MeshResource {
        switch category {
        case "container":
            return .generateCylinder(height: size.y, radius: max(size.x, size.z) / 2)
        case "flatSurface":
            return .generateBox(width: size.x, height: min(size.y, 0.04), depth: size.z)
        case "uprightObject":
            return .generateBox(width: size.x, height: max(size.y, size.x), depth: size.z)
        case "marker":
            return .generateBox(width: size.x, height: size.y, depth: min(size.z, 0.05))
        case "smallObject":
            fallthrough
        default:
            return .generateBox(width: size.x, height: size.y, depth: size.z)
        }
    }

    private func addSemanticDetails(to entity: ModelEntity, for object: WorldObjectSpec) {
        if isSurfaceLike(object) {
            addSurfaceDetails(to: entity, size: object.size)
        } else if isSnackBag(object) {
            addSnackBagDetails(to: entity, size: object.size)
        } else if isBasket(object) {
            addBasketDetails(to: entity, size: object.size)
        } else if isApple(object) {
            addAppleDetails(to: entity, size: object.size)
        } else if isPaperBag(object) {
            addPaperBagDetails(to: entity, size: object.size)
        } else if isPaymentReader(object) {
            addPaymentReaderDetails(to: entity, size: object.size)
        } else if isPersonMarker(object) {
            addPersonMarkerDetails(to: entity, size: object.size)
        } else if isMenuLike(object) {
            addMenuDetails(to: entity, size: object.size)
        }
    }

    private func addSurfaceDetails(to entity: ModelEntity, size: SIMD3<Float>) {
        entity.addChild(childBox(
            name: "\(entity.name)_front_lip",
            size: [size.x, max(0.012, size.y * 0.20), 0.018],
            position: [0, size.y / 2 + 0.008, size.z / 2 - 0.018],
            color: UIColor.brown.withAlphaComponent(0.72)
        ))
    }

    private func addSnackBagDetails(to entity: ModelEntity, size: SIMD3<Float>) {
        entity.addChild(childBox(
            name: "\(entity.name)_top_seal",
            size: [size.x * 0.88, max(0.012, size.y * 0.12), 0.008],
            position: [0, size.y * 0.42, size.z * 0.18],
            color: .white
        ))
        addMiniText(
            "CHIPS",
            to: entity,
            position: [-size.x * 0.28, -size.y * 0.08, size.z * 0.20],
            color: .white,
            fontSize: 0.026
        )
    }

    private func addBasketDetails(to entity: ModelEntity, size: SIMD3<Float>) {
        let handleHeight = size.y * 0.55
        let handleY = size.y * 0.35
        entity.addChild(childBox(
            name: "\(entity.name)_left_handle",
            size: [0.014, handleHeight, 0.014],
            position: [-size.x * 0.32, handleY, 0],
            color: .white
        ))
        entity.addChild(childBox(
            name: "\(entity.name)_right_handle",
            size: [0.014, handleHeight, 0.014],
            position: [size.x * 0.32, handleY, 0],
            color: .white
        ))
        entity.addChild(childBox(
            name: "\(entity.name)_handle_top",
            size: [size.x * 0.64, 0.014, 0.014],
            position: [0, handleY + handleHeight / 2, 0],
            color: .white
        ))
    }

    private func addAppleDetails(to entity: ModelEntity, size: SIMD3<Float>) {
        let stemHeight = max(0.028, size.y * 0.24)
        let stem = ModelEntity(
            mesh: .generateCylinder(height: stemHeight, radius: max(0.006, size.x * 0.07)),
            materials: [material(.brown)]
        )
        stem.name = "\(entity.name)_stem"
        stem.position = [0, size.y / 2 + stemHeight / 2 - 0.004, 0]
        entity.addChild(stem)
    }

    private func addPaperBagDetails(to entity: ModelEntity, size: SIMD3<Float>) {
        let handleSize = SIMD3<Float>(0.018, max(0.035, size.y * 0.32), 0.014)
        entity.addChild(childBox(
            name: "\(entity.name)_left_handle",
            size: handleSize,
            position: [-size.x * 0.20, size.y * 0.55, size.z * 0.42],
            color: UIColor.brown.withAlphaComponent(0.85)
        ))
        entity.addChild(childBox(
            name: "\(entity.name)_right_handle",
            size: handleSize,
            position: [size.x * 0.20, size.y * 0.55, size.z * 0.42],
            color: UIColor.brown.withAlphaComponent(0.85)
        ))
    }

    private func addPaymentReaderDetails(to entity: ModelEntity, size: SIMD3<Float>) {
        entity.addChild(childBox(
            name: "\(entity.name)_screen",
            size: [size.x * 0.70, size.y * 0.18, 0.008],
            position: [0, size.y * 0.20, size.z / 2 + 0.006],
            color: .black
        ))
        entity.addChild(childBox(
            name: "\(entity.name)_tap_area",
            size: [size.x * 0.42, size.y * 0.12, 0.009],
            position: [0, -size.y * 0.16, size.z / 2 + 0.008],
            color: .systemGreen
        ))
    }

    private func addPersonMarkerDetails(to entity: ModelEntity, size: SIMD3<Float>) {
        let head = ModelEntity(
            mesh: .generateSphere(radius: max(0.035, size.x * 0.55)),
            materials: [material(UIColor.systemPurple.withAlphaComponent(0.82))]
        )
        head.name = "\(entity.name)_head"
        head.position = [0, size.y / 2 + max(0.035, size.x * 0.55), 0]
        entity.addChild(head)
    }

    private func addMenuDetails(to entity: ModelEntity, size: SIMD3<Float>) {
        addMiniText(
            "MENU",
            to: entity,
            position: [-size.x * 0.34, size.y * 0.05, size.z / 2 + 0.006],
            color: .white,
            fontSize: 0.024
        )
    }

    private func childBox(
        name: String,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        color: UIColor
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(width: size.x, height: size.y, depth: size.z),
            materials: [material(color)]
        )
        entity.name = name
        entity.position = position
        return entity
    }

    private func addMiniText(
        _ text: String,
        to entity: ModelEntity,
        position: SIMD3<Float>,
        color: UIColor,
        fontSize: CGFloat
    ) {
        let textEntity = ModelEntity(
            mesh: .generateText(
                text,
                extrusionDepth: 0.001,
                font: .boldSystemFont(ofSize: fontSize),
                containerFrame: .zero,
                alignment: .left,
                lineBreakMode: .byClipping
            ),
            materials: [material(color)]
        )
        textEntity.name = "\(entity.name)_detail_text"
        textEntity.position = position
        entity.addChild(textEntity)
    }

    private func material(_ color: UIColor) -> SimpleMaterial {
        SimpleMaterial(color: color, isMetallic: false)
    }

    private func isSnackBag(_ object: WorldObjectSpec) -> Bool {
        objectMatches(object, ["chips", "snack"])
    }

    private func isBasket(_ object: WorldObjectSpec) -> Bool {
        objectMatches(object, ["basket"])
    }

    private func isPaperBag(_ object: WorldObjectSpec) -> Bool {
        objectMatches(object, ["paper bag", "paper_bag"])
    }

    private func isApple(_ object: WorldObjectSpec) -> Bool {
        objectMatches(object, ["apple", "fruit"])
    }

    private func isPaymentReader(_ object: WorldObjectSpec) -> Bool {
        if object.assetCard?.assetKind == .paymentDevice {
            return true
        }
        return objectMatches(object, ["payment", "terminal", "reader", "card"])
            || object.kind == .cardReader
    }

    private func isPersonMarker(_ object: WorldObjectSpec) -> Bool {
        if object.assetCard?.assetKind == .personMarker {
            return true
        }
        return objectMatches(object, ["cashier", "vendor", "barista", "clerk", "server", "attendant", "seller", "staff"])
            || object.kind == .npcMarker
    }

    private func isMenuLike(_ object: WorldObjectSpec) -> Bool {
        if object.assetCard?.assetKind == .menu {
            return true
        }
        switch object.kind {
        case .menu:
            return true
        case .generic(let category):
            return category == "uprightObject"
        default:
            return objectMatches(object, ["menu", "sign", "poster", "placard"])
        }
    }

    private func isSurfaceLike(_ object: WorldObjectSpec) -> Bool {
        if object.assetCard?.assetKind == .surface {
            return true
        }
        switch object.kind {
        case .counter:
            return true
        case .generic(let category):
            return category == "flatSurface"
                || objectMatches(object, ["counter", "surface", "table", "stand", "stall", "desk"])
        default:
            return objectMatches(object, ["counter", "surface", "table", "stand", "stall", "desk"])
        }
    }

    private func isCup(_ object: WorldObjectSpec) -> Bool {
        if object.assetCard?.assetKind == .cup {
            return true
        }
        return object.kind == .cup || objectMatches(object, ["cup", "coffee"])
    }

    private func objectMatches(_ object: WorldObjectSpec, _ keywords: [String]) -> Bool {
        let haystack = "\(object.id) \(object.displayName) \(object.description)"
            .lowercased()
        return keywords.contains { haystack.contains($0) }
    }

    private func addLabel(
        _ text: String,
        to entity: ModelEntity,
        yOffset: Float,
        compact: Bool = false
    ) {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.002,
            font: .systemFont(ofSize: compact ? 0.018 : 0.024),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let material = SimpleMaterial(color: .white, isMetallic: false)
        let label = ModelEntity(mesh: mesh, materials: [material])
        label.name = "\(entity.name)_label"
        label.position = [compact ? -0.035 : -0.045, yOffset, 0]
        entity.addChild(label)
    }

    private func addVisualAssetBadge(
        _ visualAsset: WorldObjectVisualAsset,
        to entity: ModelEntity,
        objectSize: SIMD3<Float>
    ) {
        guard visualAsset.status == .realized else { return }

        let maxDimension = max(objectSize.x, max(objectSize.y, objectSize.z))
        let radius = max(0.035, min(0.06, maxDimension * 0.16))
        let badgeMaterial = SimpleMaterial(color: UIColor.systemCyan.withAlphaComponent(0.88), isMetallic: false)
        let badge = ModelEntity(mesh: .generateSphere(radius: radius), materials: [badgeMaterial])
        badge.name = "\(entity.name)_sam3d_asset_badge"
        badge.position = [
            objectSize.x / 2 + radius * 0.9,
            objectSize.y + radius * 1.8,
            0
        ]
        entity.addChild(badge)

        let labelMesh = MeshResource.generateText(
            "SAM3D",
            extrusionDepth: 0.001,
            font: .boldSystemFont(ofSize: 0.024),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let label = ModelEntity(mesh: labelMesh, materials: [SimpleMaterial(color: .cyan, isMetallic: false)])
        label.name = "\(entity.name)_sam3d_asset_label"
        label.position = [-0.06, radius * 1.35, 0]
        badge.addChild(label)
    }

    private func isNativeRealityAsset(_ visualAsset: WorldObjectVisualAsset) -> Bool {
        guard visualAsset.status == .realized,
              let localURL = visualAsset.localURL else { return false }

        let fileExtension = localURL.pathExtension.lowercased()
        switch visualAsset.format {
        case .usd:
            return ["usd", "usda", "usdc", "usdz"].contains(fileExtension)
        case .usdz:
            return fileExtension == "usdz"
        case .gaussianSplatPLY, .primitiveProxy:
            return false
        }
    }

    private func addGeneratedModelAsset(
        _ visualAsset: WorldObjectVisualAsset,
        to entity: ModelEntity,
        object: WorldObjectSpec
    ) {
        let objectSize = object.size
        guard let modelURL = visualAsset.localURL else {
            addVisualAssetBadge(visualAsset, to: entity, objectSize: objectSize)
            return
        }

        Task { @MainActor in
            do {
                let modelEntity = try await Entity(contentsOf: modelURL)
                modelEntity.name = "\(entity.name)_generated_model"
                fitGeneratedModel(modelEntity, for: object)
                entity.addChild(modelEntity)
            } catch {
                if visualAsset.previewLocalURL != nil {
                    addGeneratedPreviewBillboard(visualAsset, to: entity, objectSize: objectSize)
                } else {
                    addVisualAssetBadge(visualAsset, to: entity, objectSize: objectSize)
                }
            }
        }
    }

    private enum GeneratedAssetPoseHint {
        case compact
        case tabletopThin
        case upright
        case container
        case shallowTray
    }

    private func fitGeneratedModel(_ modelEntity: Entity, for object: WorldObjectSpec) {
        let objectSize = object.size
        let bounds = modelEntity.visualBounds(relativeTo: modelEntity)
        let extents = bounds.extents
        guard extents.x.isFinite,
              extents.y.isFinite,
              extents.z.isFinite else { return }

        let targetVisualSize = generatedVisualTargetSize(for: object)
        let poseHint = generatedAssetPoseHint(for: object)
        let bestRotation = canonicalGeneratedAssetRotation(for: object) ?? bestGeneratedAssetRotation(
            boundsMin: bounds.min,
            boundsMax: bounds.max,
            targetSize: targetVisualSize,
            object: object,
            hint: poseHint
        )
        let rotatedBounds = generatedAssetBounds(
            min: bounds.min,
            max: bounds.max,
            rotation: bestRotation
        )
        let safeExtents = SIMD3<Float>(
            max(rotatedBounds.extents.x, 0.001),
            max(rotatedBounds.extents.y, 0.001),
            max(rotatedBounds.extents.z, 0.001)
        )
        let targetSize = SIMD3<Float>(
            max(targetVisualSize.x * 0.94, 0.025),
            max(targetVisualSize.y * 0.94, 0.025),
            max(targetVisualSize.z * 0.94, 0.025)
        )
        let scaleFactor = min(
            min(targetSize.x / safeExtents.x, targetSize.y / safeExtents.y),
            targetSize.z / safeExtents.z
        )
        guard scaleFactor.isFinite, scaleFactor > 0 else { return }

        let clampedScale = min(max(scaleFactor, 0.001), 100)
        modelEntity.orientation = bestRotation
        modelEntity.scale = SIMD3<Float>(repeating: clampedScale)
        modelEntity.position = [
            -rotatedBounds.center.x * clampedScale,
            -objectSize.y / 2 - rotatedBounds.min.y * clampedScale,
            -rotatedBounds.center.z * clampedScale
        ]
    }

    private func generatedAssetPoseHint(for object: WorldObjectSpec) -> GeneratedAssetPoseHint {
        if let orientationHint = object.assetCard?.orientationHint {
            switch orientationHint {
            case .horizontalSurface, .tabletopFlat:
                return .tabletopThin
            case .uprightFacingLearner:
                return .upright
            case .openTopUpright:
                return object.assetCard?.assetKind == .cup ? .upright : .container
            case .shallowTray:
                return .shallowTray
            case .compact:
                return .compact
            }
        }

        if isPaymentReader(object) || objectMatches(object, ["wallet", "card"]) {
            return .tabletopThin
        }
        if isPersonMarker(object) || isMenuLike(object) {
            return .upright
        }
        if isBasket(object) || isPaperBag(object) {
            return .container
        }
        return .compact
    }

    private func generatedVisualTargetSize(for object: WorldObjectSpec) -> SIMD3<Float> {
        if let targetSize = object.assetCard?.targetSize {
            return targetSize
        }

        if isPersonMarker(object) {
            return [
                max(object.size.x, 0.10),
                max(object.size.y, 0.24),
                max(object.size.z, 0.10)
            ]
        }
        if isMenuLike(object) {
            return [
                max(object.size.x, 0.32),
                max(object.size.y, 0.42),
                max(object.size.z, 0.045)
            ]
        }
        if isPaymentReader(object) {
            return [
                max(object.size.x, 0.16),
                max(object.size.y, 0.045),
                max(object.size.z, 0.12)
            ]
        }
        return object.size
    }

    private func canonicalGeneratedAssetRotation(for object: WorldObjectSpec) -> simd_quatf? {
        guard let canonicalPose = object.visualAsset?.canonicalPose,
              let upAxis = localAxisVector(canonicalPose.upAxis) else {
            return nil
        }

        let localUp = simd_normalize(upAxis)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let upRotation = simd_quatf(from: localUp, to: worldUp)

        guard let frontAxis = localAxisVector(canonicalPose.frontAxis) else {
            return upRotation
        }

        let rotatedFront = upRotation.act(frontAxis)
        let horizontalFront = SIMD3<Float>(rotatedFront.x, 0, rotatedFront.z)
        guard simd_length(horizontalFront) > 0.001 else {
            return upRotation
        }

        let faceLearnerRotation = simd_quatf(
            from: simd_normalize(horizontalFront),
            to: SIMD3<Float>(0, 0, 1)
        )
        return faceLearnerRotation * upRotation
    }

    private func localAxisVector(_ axis: String?) -> SIMD3<Float>? {
        guard let axis else { return nil }
        switch axis.replacingOccurrences(of: " ", with: "").uppercased() {
        case "+X":
            return [1, 0, 0]
        case "-X":
            return [-1, 0, 0]
        case "+Y":
            return [0, 1, 0]
        case "-Y":
            return [0, -1, 0]
        case "+Z":
            return [0, 0, 1]
        case "-Z":
            return [0, 0, -1]
        default:
            return nil
        }
    }

    private func bestGeneratedAssetRotation(
        boundsMin: SIMD3<Float>,
        boundsMax: SIMD3<Float>,
        targetSize: SIMD3<Float>,
        object: WorldObjectSpec,
        hint: GeneratedAssetPoseHint
    ) -> simd_quatf {
        generatedAssetRotationCandidates(for: object, hint: hint).min { lhs, rhs in
            let lhsBounds = generatedAssetBounds(min: boundsMin, max: boundsMax, rotation: lhs)
            let rhsBounds = generatedAssetBounds(min: boundsMin, max: boundsMax, rotation: rhs)
            let lhsScore = generatedAssetOrientationScore(
                extents: lhsBounds.extents,
                targetSize: targetSize,
                rotation: lhs,
                object: object,
                hint: hint
            )
            let rhsScore = generatedAssetOrientationScore(
                extents: rhsBounds.extents,
                targetSize: targetSize,
                rotation: rhs,
                object: object,
                hint: hint
            )
            return lhsScore < rhsScore
        } ?? simd_quatf(angle: 0, axis: [0, 1, 0])
    }

    private func generatedAssetRotationCandidates(
        for object: WorldObjectSpec,
        hint: GeneratedAssetPoseHint
    ) -> [simd_quatf] {
        let angles: [Float] = [0, .pi / 2, .pi, -.pi / 2]

        if shouldLiftGeneratedAssetBeforeYaw(object, hint: hint) {
            let liftRotations = [
                simd_quatf(angle: .pi / 2, axis: [0, 0, 1]),
                simd_quatf(angle: -.pi / 2, axis: [0, 0, 1]),
                simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]),
                simd_quatf(angle: .pi / 2, axis: [1, 0, 0]),
                simd_quatf(angle: 0, axis: [0, 1, 0])
            ]
            return liftRotations.flatMap { liftRotation in
                angles.map { yAngle in
                    simd_quatf(angle: yAngle, axis: [0, 1, 0]) * liftRotation
                }
            }
        }

        if hint == .upright {
            return angles.map { simd_quatf(angle: $0, axis: [0, 1, 0]) }
        }

        var rotations: [simd_quatf] = []
        rotations.reserveCapacity(64)

        for xAngle in angles {
            for yAngle in angles {
                for zAngle in angles {
                    let xRotation = simd_quatf(angle: xAngle, axis: [1, 0, 0])
                    let yRotation = simd_quatf(angle: yAngle, axis: [0, 1, 0])
                    let zRotation = simd_quatf(angle: zAngle, axis: [0, 0, 1])
                    rotations.append(zRotation * yRotation * xRotation)
                }
            }
        }

        return rotations
    }

    private func shouldLiftGeneratedAssetBeforeYaw(
        _ object: WorldObjectSpec,
        hint: GeneratedAssetPoseHint
    ) -> Bool {
        if hint == .container {
            return true
        }
        if object.assetCard?.assetKind == .cup {
            return true
        }
        return isBasket(object) || isPaperBag(object)
    }

    private func generatedAssetBounds(
        min boundsMin: SIMD3<Float>,
        max boundsMax: SIMD3<Float>,
        rotation: simd_quatf
    ) -> (min: SIMD3<Float>, max: SIMD3<Float>, center: SIMD3<Float>, extents: SIMD3<Float>) {
        let corners = [
            SIMD3<Float>(boundsMin.x, boundsMin.y, boundsMin.z),
            SIMD3<Float>(boundsMin.x, boundsMin.y, boundsMax.z),
            SIMD3<Float>(boundsMin.x, boundsMax.y, boundsMin.z),
            SIMD3<Float>(boundsMin.x, boundsMax.y, boundsMax.z),
            SIMD3<Float>(boundsMax.x, boundsMin.y, boundsMin.z),
            SIMD3<Float>(boundsMax.x, boundsMin.y, boundsMax.z),
            SIMD3<Float>(boundsMax.x, boundsMax.y, boundsMin.z),
            SIMD3<Float>(boundsMax.x, boundsMax.y, boundsMax.z)
        ]

        var rotatedMin = SIMD3<Float>(
            Float.greatestFiniteMagnitude,
            Float.greatestFiniteMagnitude,
            Float.greatestFiniteMagnitude
        )
        var rotatedMax = SIMD3<Float>(
            -Float.greatestFiniteMagnitude,
            -Float.greatestFiniteMagnitude,
            -Float.greatestFiniteMagnitude
        )

        for corner in corners {
            let rotated = rotation.act(corner)
            rotatedMin = SIMD3<Float>(
                Swift.min(rotatedMin.x, rotated.x),
                Swift.min(rotatedMin.y, rotated.y),
                Swift.min(rotatedMin.z, rotated.z)
            )
            rotatedMax = SIMD3<Float>(
                Swift.max(rotatedMax.x, rotated.x),
                Swift.max(rotatedMax.y, rotated.y),
                Swift.max(rotatedMax.z, rotated.z)
            )
        }

        let extents = rotatedMax - rotatedMin
        let center = (rotatedMin + rotatedMax) / 2
        return (rotatedMin, rotatedMax, center, extents)
    }

    private func generatedAssetOrientationScore(
        extents: SIMD3<Float>,
        targetSize: SIMD3<Float>,
        rotation: simd_quatf,
        object: WorldObjectSpec,
        hint: GeneratedAssetPoseHint
    ) -> Float {
        let safeExtents = SIMD3<Float>(
            max(extents.x, 0.001),
            max(extents.y, 0.001),
            max(extents.z, 0.001)
        )
        let safeTarget = SIMD3<Float>(
            max(targetSize.x, 0.001),
            max(targetSize.y, 0.001),
            max(targetSize.z, 0.001)
        )
        let maxExtent = max(safeExtents.x, max(safeExtents.y, safeExtents.z))
        let maxTarget = max(safeTarget.x, max(safeTarget.y, safeTarget.z))
        let shapeScore =
            abs(safeExtents.x / maxExtent - safeTarget.x / maxTarget) +
            abs(safeExtents.y / maxExtent - safeTarget.y / maxTarget) +
            abs(safeExtents.z / maxExtent - safeTarget.z / maxTarget)
        let horizontalExtent = max(safeExtents.x, safeExtents.z)

        let semanticBias = generatedAssetSemanticRotationBias(
            rotation: rotation,
            object: object,
            hint: hint
        )

        switch hint {
        case .tabletopThin:
            return shapeScore + 3.0 * (safeExtents.y / horizontalExtent) + semanticBias
        case .upright:
            return shapeScore + 3.0 * (horizontalExtent / safeExtents.y) + semanticBias
        case .container:
            return shapeScore + 1.5 * abs((safeExtents.y / horizontalExtent) - 0.55) + semanticBias
        case .shallowTray:
            return shapeScore + 4.0 * (safeExtents.y / horizontalExtent) + semanticBias
        case .compact:
            return shapeScore + semanticBias
        }
    }

    private func generatedAssetSemanticRotationBias(
        rotation: simd_quatf,
        object: WorldObjectSpec,
        hint: GeneratedAssetPoseHint
    ) -> Float {
        guard shouldLiftGeneratedAssetBeforeYaw(object, hint: hint) else {
            return 0
        }

        let worldUp = SIMD3<Float>(0, 1, 0)
        let localXAsUp = max(0, simd_dot(simd_normalize(rotation.act([1, 0, 0])), worldUp))
        let localZAsUp = max(0, simd_dot(simd_normalize(rotation.act([0, 0, 1])), worldUp))
        let localYAsUp = max(0, simd_dot(simd_normalize(rotation.act([0, 1, 0])), worldUp))

        // SAM3D image-conditioned meshes do not expose a stable canonical up
        // axis. In current bag/basket/cup outputs, the usable upright direction
        // most often lands on local Z; prefer that strongly, while still
        // allowing local X as a fallback for older generated assets.
        return -4.0 * localZAsUp - 1.0 * localXAsUp + 0.5 * localYAsUp
    }

    private func addGeneratedPreviewBillboard(
        _ visualAsset: WorldObjectVisualAsset,
        to entity: ModelEntity,
        objectSize: SIMD3<Float>
    ) {
        guard let previewURL = visualAsset.previewLocalURL,
              let imageData = try? Data(contentsOf: previewURL),
              let image = UIImage(data: imageData),
              let cgImage = image.cgImage,
              let texture = try? TextureResource.generate(
                from: cgImage,
                options: .init(semantic: .color)
              ) else {
            addVisualAssetBadge(visualAsset, to: entity, objectSize: objectSize)
            return
        }

        var material = UnlitMaterial()
        material.color = PhysicallyBasedMaterial.BaseColor(texture: .init(texture))

        let height = max(objectSize.y, 0.08)
        let width = max(0.08, max(objectSize.x, objectSize.z))
        let billboard = ModelEntity(
            mesh: .generatePlane(width: width, height: height),
            materials: [material]
        )
        billboard.name = "\(entity.name)_generated_preview"
        billboard.position = [0, 0, objectSize.z / 2 + 0.004]
        entity.addChild(billboard)

        addVisualAssetBadge(visualAsset, to: entity, objectSize: objectSize)
    }

    private func normalizedObjectId(for entity: Entity) -> String? {
        if entitiesById[entity.name] != nil {
            return entity.name
        }

        var parent = entity.parent
        while let current = parent {
            if entitiesById[current.name] != nil {
                return current.name
            }
            parent = current.parent
        }

        return nil
    }
}

extension InteractionKind {
    var displayDescription: String {
        switch self {
        case .indicate(let objectId):
            return "indicate \(objectId)"
        case .tap(let objectId):
            return "tap \(objectId)"
        case .drag(let objectId):
            return "drag \(objectId)"
        case .place(let objectId, let targetId):
            return "place \(objectId) on \(targetId)"
        case .gesture(let gesture, let targetId):
            if let targetId {
                return "\(gesture.rawValue) at \(targetId)"
            }
            return gesture.rawValue
        }
    }
}

extension GenerationOutcome {
    var shortDescription: String {
        switch self {
        case .success:
            return "success"
        case .jsonParseError(let message):
            return "JSON parse error: \(message)"
        case .schemaValidationError(let message):
            return "schema error: \(message)"
        case .planValidationError(let error):
            return "validation error: \(error.localizedDescription)"
        case .llmCallError(let message):
            return "LLM error: \(message)"
        }
    }
}

extension GenerationStage {
    var title: String {
        switch self {
        case .objectGeneration:
            return "object generation"
        case .taskGeneration:
            return "task generation"
        case .validation:
            return "validation"
        case .fullPipeline:
            return "full pipeline"
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension WorldObjectColor {
    var uiColor: UIColor {
        switch self {
        case .brown:
            return .brown
        case .red:
            return .systemRed
        case .blue:
            return .systemBlue
        case .cyan:
            return .cyan
        case .yellow:
            return .systemYellow
        case .green:
            return .systemGreen
        case .gray:
            return .systemGray
        case .purple:
            return .systemPurple
        }
    }
}

#Preview(windowStyle: .automatic) {
    InteractionWorldTestView()
        .environmentObject(InteractionWorldRuntime())
}
