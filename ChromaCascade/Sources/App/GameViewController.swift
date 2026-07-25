import SpriteKit
import UIKit

final class GameViewController: UIViewController {

    private var skView: SKView {
        // swiftlint:disable:next force_cast
        view as! SKView
    }

    override func loadView() {
        let view = SKView(frame: UIScreen.main.bounds)
        view.backgroundColor = Theme.backgroundTop
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard skView.scene == nil, skView.bounds.width > 0 else { return }
        // The scene is presented only once the view has its real size, so the
        // layout maths sees the device's actual bounds and safe areas.
        let scene = MenuScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    override var prefersStatusBarHidden: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
