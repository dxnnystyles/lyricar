import SwiftUI

struct RootView: View {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.stage.ignoresSafeArea()
            if model.isConnected {
                NowPlayingView(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ConnectView(model: model)
                    .transition(.opacity.combined(with: .offset(y: -12)))
            }
        }
        .id(model.theme)
        .animation(Theme.settle, value: model.isConnected)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setPhoneActive(phase == .active)
        }
    }
}
