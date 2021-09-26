//
//  ContentView.swift
//  ImageAnchor
//
//  Created by Nien Lam on 9/21/21.
//  Copyright © 2021 Line Break, LLC. All rights reserved.
//

import SwiftUI
import ARKit
import RealityKit
import Combine


// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    let uiSignal = PassthroughSubject<UISignal, Never>()
    
    enum UISignal {
    }
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
}


// MARK: - AR View.
struct ARViewContainer: UIViewRepresentable {
    let viewModel: ViewModel
    
    func makeUIView(context: Context) -> ARView {
        SimpleARView(frame: .zero, viewModel: viewModel)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class SimpleARView: ARView, ARSessionDelegate {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var subscriptions = Set<AnyCancellable>()
    
    // Dictionary for tracking image anchors.
    var imageAnchorToEntity: [ARImageAnchor: AnchorEntity] = [:]

    // Materials array for animation.
    
    var materialsArray = [RealityKit.Material]()

    // Index for animation.
    var materialIdx = 0

    // Variable adjust animated texture timing.
    var lastUpdateTime = Date()

    // Using plane entity for animation.
    var planeEntity: ModelEntity?
    
    // Example box entity.
    var boxEntity: ModelEntity?
    
    // Variable for tracking ambient light intensity.
    var ambientIntensity: Double = 0


    init(frame: CGRect, viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        setupScene()
        
        setupMaterials()
    }
    
    func setupScene() {
        // Setup world tracking and plane detection.
        let configuration = ARImageTrackingConfiguration()
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]


        // TODO: Update target image and physical width in meters. //////////////////////////////////////
        let targetImage    = "itp-logo.jpg"
        let physicalWidth  = 0.1524
        
        if let refImage = UIImage(named: targetImage)?.cgImage {
            let arReferenceImage = ARReferenceImage(refImage, orientation: .up, physicalWidth: physicalWidth)
            var set = Set<ARReferenceImage>()
            set.insert(arReferenceImage)
            configuration.trackingImages = set
        } else {
            print("❗️ Error loading target image")
        }
        

        arView.session.run(configuration)
        
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            // Call renderLoop method on every frame.
            self.renderLoop()
        }.store(in: &subscriptions)
        
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)

        // Set session delegate.
        arView.session.delegate = self
    }
    
    // Hide/Show active tetromino.
    func processUISignal(_ signal: ViewModel.UISignal) {
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        anchors.compactMap { $0 as? ARImageAnchor }.forEach {
            // Create anchor from image.
            let anchorEntity = AnchorEntity(anchor: $0)
            
            // Track image anchors added to scene.
            imageAnchorToEntity[$0] = anchorEntity
            
            // Add anchor to scene.
            arView.scene.addAnchor(anchorEntity)
            
            // Call setup method for entities.
            // IMPORTANT: Play USDZ animations after entity is added to the scene.
            setupEntities(anchorEntity: anchorEntity)
        }
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if let intensity = frame.lightEstimate?.ambientIntensity {
            ambientIntensity = intensity
        }
    }


    // TODO: Do any material setup work. //////////////////////////////////////

    func setupMaterials() {
        // Create array of materials holding horse textures.
        for idx in 1...11 {
            var unlitMaterial = UnlitMaterial()

            let imageNamed = "horse-\(idx)"
            unlitMaterial.color.texture = UnlitMaterial.Texture.init(try! .load(named: imageNamed))
            unlitMaterial.color.tint    = UIColor.white.withAlphaComponent(0.999999)

            materialsArray.append(unlitMaterial)
        }
    }


    // TODO: Setup entities. //////////////////////////////////////
    // IMPORTANT: Attach to anchor entity. Called when image target is found.

    func setupEntities(anchorEntity: AnchorEntity) {
        // Checker material.
        var checkerMaterial = PhysicallyBasedMaterial()
        let texture = PhysicallyBasedMaterial.Texture.init(try! .load(named: "checker.png"))
        checkerMaterial.baseColor.texture = texture

        // Setup example box entity.
        let boxMesh = MeshResource.generateBox(size: [0.1, 0.1, 0.1], cornerRadius: 0.0)
        boxEntity = ModelEntity(mesh: boxMesh, materials: [checkerMaterial])

        // Position and add box entity to anchor.
        boxEntity?.position.y = 0.05
        anchorEntity.addChild(boxEntity!)
         
        // Setup, position and add plane entity to anchor.
        planeEntity = try! Entity.loadModel(named: "plane.usda")
        planeEntity?.scale = [0.5, 0.5, 0.5]
        planeEntity?.position.y = 0.2
        anchorEntity.addChild(planeEntity!)
    }
    

    // TODO: Animate entities. //////////////////////////////////////

    func renderLoop() {
            
        // Time interval from last animated material update.
        let currentTime  = Date()
        let timeInterval = currentTime.timeIntervalSince(lastUpdateTime)

        // Animate material every 1 / 15 of second.
        if timeInterval > 1 / 15 {
            // Cycle material index.
            materialIdx = (materialIdx < materialsArray.count - 1) ? materialIdx + 1 : 0

            // Get and set material from array.
            let material = materialsArray[materialIdx]
            planeEntity?.model?.materials = [material]

            // Remember last update time.
            lastUpdateTime = currentTime
        }


        // Spin boxEntity.
        boxEntity?.orientation *= simd_quatf(angle: 0.02, axis: [0, 1, 0])
 
        
        // Sensor Value: ambientIntensity
        // print(ambientIntensity)
    }
}
