import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CarPlayLyricsController?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated {
            let controller = CarPlayLyricsController(engine: AppModel.shared.engine, interfaceController: interfaceController, scene: scene)
            controller.install()
            self.controller = controller
            AppModel.shared.setCarPlayConnected(true)
            AppModel.shared.engine.refreshNow()
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated {
            controller?.uninstall()
            controller = nil
            AppModel.shared.setCarPlayConnected(false)
        }
    }
}
