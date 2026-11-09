import CoreAudioKit
import SwiftUI

@objc(Synth05AudioUnitViewController)
final class Synth05AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var unit:HostedSynthAudioUnit?
    private var hostedEngine:SynthEngine?
    #if os(macOS)
    private var hosting:NSHostingController<ContentView>?
    override func loadView() { view=NSView(frame:NSRect(x:0,y:0,width:1120,height:920));install() }
    #else
    private var hosting:UIHostingController<ContentView>?
    override func viewDidLoad() { super.viewDidLoad();install() }
    #endif
    nonisolated func createAudioUnit(with componentDescription:AudioComponentDescription) throws -> AUAudioUnit {
        let unit=try HostedSynthAudioUnit(componentDescription:componentDescription)
        DispatchQueue.main.async { [weak self] in self?.unit=unit;self?.install() }
        return unit
    }
    @MainActor private func install() {
        guard isViewLoaded,hosting==nil,let unit else { return }
        let engine=SynthEngine(hostedUnit:unit);hostedEngine=engine
        #if os(macOS)
        let hosting=NSHostingController(rootView:ContentView(engine:engine))
        addChild(hosting);view.addSubview(hosting.view)
        preferredContentSize=NSSize(width:1120,height:920)
        #else
        let hosting=UIHostingController(rootView:ContentView(engine:engine))
        addChild(hosting);view.addSubview(hosting.view);hosting.didMove(toParent:self)
        preferredContentSize=CGSize(width:740,height:850)
        #endif
        hosting.view.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),hosting.view.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo:view.topAnchor),hosting.view.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        self.hosting=hosting
    }
}
