import UIKit
import SceneKit
import ARKit
import Vision
import SpriteKit

class ViewController: UIViewController, ARSCNViewDelegate {
    
    // SCENE
    @IBOutlet var sceneView: ARSCNView!
    let bubbleDepth: Float = 0.01 // the 'depth' of 3D text
    var latestPrediction: String = "…" // a variable containing the latest CoreML prediction
    let minimumConfidenceThreshhold: VNConfidence = 0.75
    var confidence: VNConfidence = 0.0
    var debugConfidence: VNConfidence = 0.10
    var identifiedLabels = [String]() //keep track of all detected obejects so far
    var touchLocation: CGPoint?
    var objectToCreate: SCNNode?
    var isScanning = true
    
    // COREML
    var visionRequests = [VNRequest]()
    let dispatchQueueML = DispatchQueue(label: "com.projectar.dispatchqueueml") // A Serial Queue
    @IBOutlet weak var debugTextView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Enable Default Lighting - makes the 3D text a bit poppier.
        sceneView.autoenablesDefaultLighting = true
        
        // Tap Gesture Recognizer
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(self.handleTapToPlace(gestureRecognizer:)))
        longPressGesture.minimumPressDuration = 1.0
        sceneView.addGestureRecognizer(longPressGesture)
        
        let tapGestureCreate = UITapGestureRecognizer(target: self, action: #selector(self.handleTapToCreate(gestureRecognizer:)))
        sceneView.addGestureRecognizer(tapGestureCreate)


        
        // Set up Vision Model
        guard let selectedModel = try? VNCoreMLModel(for: Inceptionv3().model) else {
            fatalError("Could not load model. Ensure model has been drag and dropped (copied) to XCode Project from https://developer.apple.com/machine-learning/ . Also ensure the model is part of a target (see: https://stackoverflow.com/questions/45884085/model-is-not-part-of-any-target-add-the-model-to-a-target-to-enable-generation ")
        }
        
        // Set up Vision-CoreML Request
        let classificationRequest = VNCoreMLRequest(model: selectedModel, completionHandler: classificationCompleteHandler)
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop // Crop from centre of images and scale to appropriate size.
        visionRequests = [classificationRequest]
        
        // Begin Loop to Update CoreML
        loopCoreMLUpdate()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        // Enable plane detection
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        
        DispatchQueue.main.async {
            guard self.isScanning else { return }
            // Do any desired updates to SceneKit here.
            guard self.confidence >= self.minimumConfidenceThreshhold else {
                return
            }
            let screenCentre = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
            
            let arHitTestResults = self.sceneView.hitTest(screenCentre, types: [.featurePoint]) // Alternatively, we could use '.existingPlaneUsingExtent' for more grounded hit-test-points.
            
            if let closestResult = arHitTestResults.first {
                // Get Coordinates of HitTest
                let transform = closestResult.worldTransform
                let worldCoord = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                
                // Create 3D Text
                if !self.identifiedLabels.contains(self.latestPrediction) {
                    //let node : SCNNode = self.createNewBubbleParentNode(self.latestPrediction)
                    let node = self.createPlaneNodeFromText(self.latestPrediction)
                    self.sceneView.scene.rootNode.addChildNode(node)
                    node.position = worldCoord
                    self.identifiedLabels.append(self.latestPrediction)
                }
            }
        }
    }
    
    // MARK: - Status Bar: Hide
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    // MARK: - Interaction
    
    @objc func handleTapToPlace(gestureRecognizer: UITapGestureRecognizer) {
        
        if gestureRecognizer.state == .ended {
            touchLocation = gestureRecognizer.location(in: sceneView)
            testAndCreateNodeToPlace()
        }
        
        
    }
    
    @objc func handleTapToCreate(gestureRecognizer: UITapGestureRecognizer) {
        
        if gestureRecognizer.state == .ended {
            touchLocation = gestureRecognizer.location(in: sceneView)
            placeNode()
        }
    }
    
    func testAndCreateNodeToPlace() {
        
        guard let location = touchLocation else { return }
        
        let hitTestResults = sceneView.hitTest(location, options: nil)
        
        guard let hitTestResult = hitTestResults.first else { return }
        
        let node = hitTestResult.node
        
        guard let geometry = node.geometry, let name = geometry.name, identifiedLabels.contains(name) else { return }
        
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        let shipNode = scene.rootNode.childNode(withName: "ship", recursively: true)
        shipNode?.scale = SCNVector3(0.5, 0.5, 0.5)
        shipNode?.pivot = SCNMatrix4MakeTranslation(0, 0, -1.0)
        objectToCreate = shipNode
        isScanning = false
        print(isScanning)
        
        
    }
    
    func placeNode() {
        
        guard let location = touchLocation, !isScanning else { return }
        let hitTestResults = sceneView.hitTest(location, types: .existingPlane)
        guard let hitTestResult = hitTestResults.first else { return }
        
        let match = hitTestResult.worldTransform
        
        guard let object = objectToCreate else { return }
        
        object.position = SCNVector3(match.columns.3.x,match.columns.3.y + 0.2, match.columns.3.z)
        
        self.sceneView.scene.rootNode.addChildNode(object)
        isScanning = true
        print(isScanning)

    }
    
    
    func createPlaneNodeFromText(_ text : String) -> SCNNode {
        // Text Billboard Constraints
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        
        //SK scene
        let skScene = SKScene(size: CGSize(width: 200, height: 200))
        skScene.backgroundColor = UIColor.clear
        let rectangle = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 200, height: 200), cornerRadius: 10)
        rectangle.fillColor = UIColor.black
        let labelNode = SKLabelNode(text: text)
        labelNode.yScale = -1
        labelNode.fontSize = 20
        labelNode.fontName = "San Fransisco"
        labelNode.position = CGPoint(x:100,y:100)
        skScene.addChild(rectangle)
        skScene.addChild(labelNode)
        
        //SCNPlane
        let plane = SCNPlane(width: 0.1, height: 0.1)
        plane.name = text
        let planeMaterial = SCNMaterial()
        planeMaterial.isDoubleSided = true
        planeMaterial.diffuse.contents = skScene
        plane.materials = [planeMaterial]
        
        let planeNode = SCNNode(geometry: plane)
        let (minBound, maxBound) = plane.boundingBox
        planeNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/2, minBound.y, 0.01/2)
        
        let planeNodeParent = SCNNode()
        planeNodeParent.addChildNode(planeNode)
        planeNodeParent.constraints = [billboardConstraint]
        
        return planeNodeParent
    }
    
    // MARK: - CoreML Vision Handling
    
    func loopCoreMLUpdate() {
        // Continuously run CoreML whenever it's ready. (Preventing 'hiccups' in Frame Rate)
        
        dispatchQueueML.async {
            // 1. Run Update.
            self.updateCoreML()
            
            // 2. Loop this function.
            self.loopCoreMLUpdate()
        }
        
    }
    
    func classificationCompleteHandler(request: VNRequest, error: Error?) {
        // Catch Errors
        if error != nil {
            print("Error: " + (error?.localizedDescription)!)
            return
        }
        guard let observations = request.results else {
            print("No results")
            return
        }
        
        // Get Classifications
        // top 2 results
        let classifications = observations[0...1]
            .compactMap({ $0 as? VNClassificationObservation })
            .map({ "\($0.identifier) \(String(format:"- %.2f", $0.confidence))" })
            .joined(separator: "\n")
        
        
        
        DispatchQueue.main.async {
            // Print Classifications
            //print(classifications)
            //print("--")
            
            // Store the latest prediction
            var objectName = "…"
            objectName = classifications.components(separatedBy: "-")[0]
            objectName = objectName.components(separatedBy: ",")[0]
            
            guard let firstObservation = observations.first, let observation = firstObservation as? VNClassificationObservation else {
                return
            }
            self.confidence = observation.confidence
            self.latestPrediction = objectName
            
            // Display Debug Text on screen
            var debugText = ""
            debugText += classifications
            if self.confidence > self.debugConfidence {
                self.debugTextView.text = debugText
            } else {
                self.debugTextView.text = "null"
            }

        }
    }
    
    func updateCoreML() {
        // Get Camera Image as RGB
        let pixbuff: CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!)
        
        // Prepare CoreML/Vision Request
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        // Run Image Request
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
        
    }
}

extension UIFont {
    // Based on: https://stackoverflow.com/questions/4713236/how-do-i-set-bold-and-italic-on-uilabel-of-iphone-ipad
    func withTraits(traits:UIFontDescriptor.SymbolicTraits...) -> UIFont {
        let descriptor = self.fontDescriptor.withSymbolicTraits(UIFontDescriptor.SymbolicTraits(traits))
        return UIFont(descriptor: descriptor!, size: 0)
    }
}
