import SwiftUI
import UIKit

private struct PapiBoundsKey: EnvironmentKey { static let defaultValue: CGRect = .zero }
private struct PapiRegionsKey: EnvironmentKey { static let defaultValue: [CGRect] = [] }
extension EnvironmentValues {
    var papiBounds: CGRect { get {self[PapiBoundsKey.self]} set {self[PapiBoundsKey.self]=newValue} }
    var papiRegions: [CGRect] { get {self[PapiRegionsKey.self]} set {self[PapiRegionsKey.self]=newValue} }
}
struct PapiRegionGeometry {
    static func largestArea(in bounds:CGRect, excluding regions:[CGRect]) -> CGRect {
        var areas = [bounds]
        for region in regions {
            areas = areas.flatMap { rect -> [CGRect] in
                let overlap = rect.intersection(region)
                guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return [rect] }
                let candidates = [CGRect(x:rect.minX,y:rect.minY,width:max(0,overlap.minX-rect.minX),height:rect.height),
                    CGRect(x:overlap.maxX,y:rect.minY,width:max(0,rect.maxX-overlap.maxX),height:rect.height),
                    CGRect(x:rect.minX,y:rect.minY,width:rect.width,height:max(0,overlap.minY-rect.minY)),
                    CGRect(x:rect.minX,y:overlap.maxY,width:rect.width,height:max(0,rect.maxY-overlap.maxY))]
                return candidates.filter {$0.width >= 44 && $0.height >= 44}
            }
        }
        return areas.max(by:{$0.width*$0.height < $1.width*$1.height}) ?? bounds
    }
}
struct PapiDeviceContainer<Content:View>:View {
    @ViewBuilder var content:()->Content
    var body:some View {
        GeometryReader { proxy in
            content().frame(maxWidth:.infinity,maxHeight:.infinity)
                .environment(\.papiRegions,regions(proxy))
                .environment(\.papiBounds,CGRect(origin:.zero,size:proxy.size))
        }.coordinateSpace(name:"PapiContainer")
            // Paint outside the measured foreground without disabling keyboard or camera cutout avoidance.
            .background {PapiBackground()}
    }
    private func regions(_ proxy:GeometryProxy)->[CGRect] {
        #if PAPI_DUO_SDK
        if #available(iOS 27.1,*) {
            return (proxy.reservedRegions(kind:.division,layoutDirectionBehavior:.fixed) + proxy.reservedRegions(kind:.occlusion,layoutDirectionBehavior:.fixed))
                .filter(\.isActive).map(\.frame)
        }
        #endif
        return []
    }
}
private struct ControlFrameKey:PreferenceKey {
    static var defaultValue:CGRect = .zero
    static func reduce(value:inout CGRect,nextValue:()->CGRect) { value=nextValue() }
}
private struct AvoidRegionModifier:ViewModifier {
    @Environment(\.papiRegions) private var regions
    @Environment(\.papiBounds) private var bounds
    @State private var frame:CGRect = .zero
    func body(content:Content)->some View {
        // Measurement is outside the translated child, so offsets do not feed back into geometry.
        content.offset(translation).background(GeometryReader { p in Color.clear.preference(key:ControlFrameKey.self,value:p.frame(in:.named("PapiContainer"))) })
            .onPreferenceChange(ControlFrameKey.self) {frame=$0}
    }
    private var translation:CGSize {
        guard frame.width > 0 else {return .zero}
        var adjusted=frame
        for region in regions where adjusted.intersects(region) {
            let options=[CGSize(width:region.minX-adjusted.maxX-4,height:0),CGSize(width:region.maxX-adjusted.minX+4,height:0),CGSize(width:0,height:region.minY-adjusted.maxY-4),CGSize(width:0,height:region.maxY-adjusted.minY+4)]
            let valid=options.filter {bounds.contains(adjusted.offsetBy(dx:$0.width,dy:$0.height))}
            if let offset=valid.min(by:{abs($0.width)+abs($0.height)<abs($1.width)+abs($1.height)}) {adjusted=adjusted.offsetBy(dx:offset.width,dy:offset.height)}
        }
        return CGSize(width:adjusted.minX-frame.minX,height:adjusted.minY-frame.minY)
    }
}
extension View {
    func papiAvoidReserved()->some View {modifier(AvoidRegionModifier())}
    @ViewBuilder func papiContainerMargins()->some View {
        #if PAPI_DUO_SDK
        if #available(iOS 27.1,*) { self.contentMargins(for:.container,edges:.horizontal) }
        else {self}
        #else
        self
        #endif
    }
}
/// The same two subviews keep identity while the bar moves. A size change does not recreate navigation or business state.
struct PapiShellLayout:Layout {
    var side:HorizontalEdge?
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {proposal.replacingUnspecifiedDimensions()}
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        guard subviews.count==2 else{return}
        if let side {
            let width:CGFloat=82
            let isLeft = side == .leading // Layout mirrors semantic positions once in RTL.
            subviews[0].place(at:CGPoint(x:bounds.minX+(isLeft ? width:0),y:bounds.minY),proposal:ProposedViewSize(width:max(0,bounds.width-width),height:bounds.height))
            subviews[1].place(at:CGPoint(x:isLeft ? bounds.minX:bounds.maxX-width,y:bounds.minY),proposal:ProposedViewSize(width:width,height:bounds.height))
        } else {
            let height=subviews[1].sizeThatFits(ProposedViewSize(width:bounds.width,height:nil)).height
            subviews[0].place(at:bounds.origin,proposal:ProposedViewSize(width:bounds.width,height:max(0,bounds.height-height)))
            subviews[1].place(at:CGPoint(x:bounds.minX,y:bounds.maxY-height),proposal:ProposedViewSize(width:bounds.width,height:height))
        }
    }
}
struct SwipeBackBridge:UIViewControllerRepresentable {
    func makeUIViewController(context:Context)->Controller {Controller()}
    func updateUIViewController(_ controller:Controller,context:Context) {}
    final class Controller:UIViewController {
        override func viewDidAppear(_ animated:Bool) {
            super.viewDidAppear(animated)
            guard let nav=navigationController, nav.viewControllers.count > 1 else{return}
            nav.interactivePopGestureRecognizer?.isEnabled=true
            nav.interactivePopGestureRecognizer?.delegate=nil
        }
    }
}
