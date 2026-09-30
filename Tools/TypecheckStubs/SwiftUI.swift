// Type-checking stand-in for the subset of SwiftUI used by Cardboard Lab.
@_exported import UIKit
@_exported import Combine

@MainActor public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}
extension Never: View { public var body: Never { fatalError() } }

@MainActor @resultBuilder public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C: View>(_ c: C) -> C { c }
    public static func buildBlock<each C: View>(_ c: repeat each C) -> TupleView<(repeat each C)> { TupleView((repeat each c)) }
    public static func buildOptional<C: View>(_ c: C?) -> C? { c }
    public static func buildEither<T: View, F: View>(first: T) -> _ConditionalContent<T, F> { _ConditionalContent() }
    public static func buildEither<T: View, F: View>(second: F) -> _ConditionalContent<T, F> { _ConditionalContent() }
    public static func buildLimitedAvailability<C: View>(_ c: C) -> AnyView { AnyView(c) }
    public static func buildExpression<C: View>(_ c: C) -> C { c }
}
extension Optional: View where Wrapped: View { public var body: Never { fatalError() } }
public struct TupleView<T>: View { public init(_ v: T) {} ; public var body: Never { fatalError() } }
public struct _ConditionalContent<T, F>: View { public var body: Never { fatalError() } }
public struct EmptyView: View { public init() {} ; public var body: Never { fatalError() } }
public struct AnyView: View { public init<V: View>(_ v: V) {} ; public var body: Never { fatalError() } }

// MARK: Layout & values
public struct Edge { public enum Set_ {}
    public struct Set: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1), bottom = Set(rawValue: 2), leading = Set(rawValue: 4), trailing = Set(rawValue: 8)
        public static let horizontal: Set = [.leading, .trailing], vertical: Set = [.top, .bottom], all: Set = [.top, .bottom, .leading, .trailing] }
}
public enum EdgeName { case top, bottom, leading, trailing }
extension Edge { public static let top = EdgeName.top, bottom = EdgeName.bottom, leading = EdgeName.leading, trailing = EdgeName.trailing }
public struct Alignment { public static let center = Alignment(), top = Alignment(), bottom = Alignment(), leading = Alignment(), trailing = Alignment(), topLeading = Alignment(), topTrailing = Alignment(), bottomLeading = Alignment(), bottomTrailing = Alignment() }
public struct HorizontalAlignment { public static let center = HorizontalAlignment(), leading = HorizontalAlignment(), trailing = HorizontalAlignment() }
public struct VerticalAlignment { public static let center = VerticalAlignment(), top = VerticalAlignment(), bottom = VerticalAlignment(), firstTextBaseline = VerticalAlignment() }
public struct UnitPoint { public init(x: CGFloat, y: CGFloat) {}
    public static let center = UnitPoint(x: 0.5, y: 0.5), top = UnitPoint(x: 0.5, y: 0), bottom = UnitPoint(x: 0.5, y: 1), leading = UnitPoint(x: 0, y: 0.5), trailing = UnitPoint(x: 1, y: 0.5), topLeading = UnitPoint(x: 0, y: 0), bottomTrailing = UnitPoint(x: 1, y: 1), topTrailing = UnitPoint(x: 1, y: 0), bottomLeading = UnitPoint(x: 0, y: 1) }
public struct Angle { public init(degrees: Double) {} ; public init(radians: Double) {} ; public static func degrees(_ d: Double) -> Angle { Angle(degrees: d) } ; public static func radians(_ r: Double) -> Angle { Angle(radians: r) } ; public static let zero = Angle(degrees: 0) }
public enum TextAlignment { case leading, center, trailing }
public enum ColorScheme { case light, dark }
public enum Visibility { case automatic, visible, hidden }
public enum ContentMode { case fit, fill }
public struct RoundedCornerStyle { public static let continuous = RoundedCornerStyle(), circular = RoundedCornerStyle() }

public struct Font {
    public struct Weight { public static let regular = Weight(), medium = Weight(), semibold = Weight(), bold = Weight(), heavy = Weight(), black = Weight() }
    public enum Design { case `default`, rounded, monospaced, serif }
    public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font { Font() }
    public static let title = Font(), headline = Font(), body = Font(), caption = Font()
    public func monospacedDigit() -> Font { self }
}

public protocol ShapeStyle {}
public struct Color: ShapeStyle, Equatable {
    public init(uiColor: UIColor) {}
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {}
    public init(white: Double, opacity: Double = 1) {}
    public static let white = Color(white: 1), black = Color(white: 0), clear = Color(white: 0, opacity: 0)
    public func opacity(_ o: Double) -> Color { self }
}
extension Color: View { public var body: Never { fatalError() } }
extension ShapeStyle where Self == Color {
    public static var white: Color { Color.white }
    public static var black: Color { Color.black }
    public static var clear: Color { Color.clear }
}

public struct Animation {
    public static func easeInOut(duration: Double) -> Animation { Animation() }
    public static func easeOut(duration: Double) -> Animation { Animation() }
    public static func easeIn(duration: Double) -> Animation { Animation() }
    public static func linear(duration: Double) -> Animation { Animation() }
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.8, blendDuration: Double = 0) -> Animation { Animation() }
    public static var easeInOut: Animation { Animation() }
    public static var spring: Animation { Animation() }
    public static var bouncy: Animation { Animation() }
    public static var snappy: Animation { Animation() }
    public func delay(_ d: Double) -> Animation { self }
    public func repeatForever(autoreverses: Bool = true) -> Animation { self }
    public func speed(_ s: Double) -> Animation { self }
}
public func withAnimation<R>(_ a: Animation? = .easeInOut, _ body: () throws -> R) rethrows -> R { try body() }

public struct AnyTransition {
    public static let opacity = AnyTransition(), scale = AnyTransition(), identity = AnyTransition()
    public static func move(edge: EdgeName) -> AnyTransition { AnyTransition() }
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition { AnyTransition() }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { AnyTransition() }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition { AnyTransition() }
    public func combined(with other: AnyTransition) -> AnyTransition { self }
    public func animation(_ a: Animation?) -> AnyTransition { self }
}

// MARK: State
@propertyWrapper public struct State<Value> {
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public var wrappedValue: Value { get { fatalError() } nonmutating set {} }
    public var projectedValue: Binding<Value> { fatalError() }
}
@propertyWrapper @dynamicMemberLookup public struct Binding<Value> {
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {}
    public var wrappedValue: Value { get { fatalError() } nonmutating set {} }
    public var projectedValue: Binding<Value> { self }
    public static func constant(_ v: Value) -> Binding<Value> { fatalError() }
    public subscript<T>(dynamicMember kp: WritableKeyPath<Value, T>) -> Binding<T> { fatalError() }
}
@propertyWrapper public struct StateObject<O: ObservableObject> {
    public init(wrappedValue: @autoclosure @escaping () -> O) {}
    public var wrappedValue: O { fatalError() }
    public var projectedValue: ObservedObject<O>.Wrapper { fatalError() }
}
@propertyWrapper public struct ObservedObject<O: ObservableObject> {
    @dynamicMemberLookup public struct Wrapper { public subscript<T>(dynamicMember kp: ReferenceWritableKeyPath<O, T>) -> Binding<T> { fatalError() } }
    public init(wrappedValue: O) {}
    public var wrappedValue: O { fatalError() }
    public var projectedValue: Wrapper { fatalError() }
}
@propertyWrapper public struct EnvironmentObject<O: ObservableObject> {
    public init() {}
    public var wrappedValue: O { fatalError() }
    public var projectedValue: ObservedObject<O>.Wrapper { fatalError() }
}

// MARK: Views
public struct Text: View {
    public init(_ s: String) {}
    public init<S: StringProtocol>(_ s: S) {}
    public init(verbatim: String) {}
    public var body: Never { fatalError() }
    public func font(_ f: Font?) -> Text { self }
    public func bold() -> Text { self }
    public func fontWeight(_ w: Font.Weight?) -> Text { self }
    public func foregroundColor(_ c: Color?) -> Text { self }
    public func tracking(_ t: CGFloat) -> Text { self }
    public func kerning(_ t: CGFloat) -> Text { self }
    public func italic() -> Text { self }
    public static func + (a: Text, b: Text) -> Text { a }
}
public struct Image: View {
    public init(systemName: String) {}
    public init(uiImage: UIImage) {}
    public init(_ name: String) {}
    public enum Interpolation { case none, low, medium, high }
    public func resizable() -> Image { self }
    public func interpolation(_ i: Interpolation) -> Image { self }
    public func renderingMode(_ m: TemplateRenderingMode?) -> Image { self }
    public enum TemplateRenderingMode { case template, original }
    public var body: Never { fatalError() }
}
public struct VStack<Content: View>: View { public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {} ; public var body: Never { fatalError() } }
public struct HStack<Content: View>: View { public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {} ; public var body: Never { fatalError() } }
public struct ZStack<Content: View>: View { public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {} ; public var body: Never { fatalError() } }
public struct Group<Content: View>: View { public init(@ViewBuilder content: () -> Content) {} ; public var body: Never { fatalError() } }
public struct Spacer: View { public init(minLength: CGFloat? = nil) {} ; public var body: Never { fatalError() } }
public struct Divider: View { public init() {} ; public var body: Never { fatalError() } }
public struct GeometryProxy { public var size: CGSize { .zero } ; public var safeAreaInsets: EdgeInsets { EdgeInsets() } }
public struct EdgeInsets { public init() {} ; public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {} ; public var top: CGFloat = 0, bottom: CGFloat = 0, leading: CGFloat = 0, trailing: CGFloat = 0 }
public struct GeometryReader<Content: View>: View { public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {} ; public var body: Never { fatalError() } }
public struct ScrollView<Content: View>: View { public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {} ; public var body: Never { fatalError() } }
public enum Axis { public struct Set: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue } ; public static let horizontal = Set(rawValue: 1), vertical = Set(rawValue: 2) } }
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    public var body: Never { fatalError() }
}
extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}
extension ForEach {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}
extension ForEach where Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {}
}
public struct Button<Label: View>: View {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {}
    public var body: Never { fatalError() }
}
extension Button where Label == Text { public init(_ title: String, action: @escaping () -> Void) {} }
public struct Toggle<Label: View>: View {
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {}
    public var body: Never { fatalError() }
}
extension Toggle where Label == Text { public init(_ title: String, isOn: Binding<Bool>) {} }
public struct TimelineView<Content: View>: View {
    public struct Context { public var date: Date { Date() } }
    public init(_ schedule: AnimationTimelineSchedule, @ViewBuilder content: @escaping (Context) -> Content) {}
    public var body: Never { fatalError() }
}
public struct AnimationTimelineSchedule { public static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule() } }

public struct Label<Title: View, Icon: View>: View {
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {}
    public var body: Never { fatalError() }
}
extension Label where Title == Text, Icon == Image { public init(_ title: String, systemImage: String) {} }

// MARK: Shapes
public protocol Shape: View {}
extension Shape {
    public func fill<S: ShapeStyle>(_ s: S) -> some View { self }
    public func stroke<S: ShapeStyle>(_ s: S, lineWidth: CGFloat = 1) -> some View { self }
    public func stroke<S: ShapeStyle>(_ s: S, style: StrokeStyle) -> some View { self }
    public func strokeBorder<S: ShapeStyle>(_ s: S, lineWidth: CGFloat = 1) -> some View { self }
    public func strokeBorder<S: ShapeStyle>(_ s: S, style: StrokeStyle) -> some View { self }
    public func trim(from: CGFloat = 0, to: CGFloat = 1) -> Self { self }
    public var body: Never { fatalError() }
}
public struct StrokeStyle { public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, dash: [CGFloat] = [], dashPhase: CGFloat = 0) {} }
public struct Capsule: Shape { public init() {} }
public struct Circle: Shape { public init() {} }
public struct Rectangle: Shape { public init() {} }
public struct RoundedRectangle: Shape { public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {} }
public struct Path: Shape {
    public init() {}
    public init(_ build: (inout Path) -> Void) {}
    public mutating func move(to p: CGPoint) {}
    public mutating func addLine(to p: CGPoint) {}
    public mutating func addLines(_ p: [CGPoint]) {}
    public mutating func closeSubpath() {}
    public mutating func addQuadCurve(to p: CGPoint, control: CGPoint) {}
}

// MARK: Buttons & gestures
public struct ButtonStyleConfiguration { public struct Label {} ; public let label = Label() ; public let isPressed = false }
extension ButtonStyleConfiguration.Label: View { public var body: Never { fatalError() } }
@MainActor public protocol ButtonStyle { associatedtype Body: View ; typealias Configuration = ButtonStyleConfiguration ; @ViewBuilder func makeBody(configuration: Configuration) -> Body }
public protocol PrimitiveButtonStyle {}
public struct PlainButtonStyle: PrimitiveButtonStyle { public init() {} }
extension PrimitiveButtonStyle where Self == PlainButtonStyle { public static var plain: PlainButtonStyle { PlainButtonStyle() } }
public struct DragGesture {
    public struct Value { public var location: CGPoint { .zero } ; public var translation: CGSize { .zero } ; public var startLocation: CGPoint { .zero } }
    public init(minimumDistance: CGFloat = 10) {}
    public func onChanged(_ f: @escaping (Value) -> Void) -> DragGesture { self }
    public func onEnded(_ f: @escaping (Value) -> Void) -> DragGesture { self }
}
public struct ContentShapeKinds {}

// MARK: Modifiers
extension View {
    public func font(_ f: Font?) -> some View { self }
    public func fontWeight(_ w: Font.Weight?) -> some View { self }
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> some View { self }
    public func foregroundColor(_ c: Color?) -> some View { self }
    public func tint(_ c: Color?) -> some View { self }
    public func tracking(_ t: CGFloat) -> some View { self }
    public func kerning(_ t: CGFloat) -> some View { self }
    public func monospacedDigit() -> some View { self }
    public func lineLimit(_ n: Int?) -> some View { self }
    public func multilineTextAlignment(_ a: TextAlignment) -> some View { self }
    public func minimumScaleFactor(_ f: CGFloat) -> some View { self }
    public func textCase(_ c: Text.Case?) -> some View { self }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { self }
    public func padding(_ length: CGFloat) -> some View { self }
    public func padding(_ insets: EdgeInsets) -> some View { self }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View { self }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment = .center) -> some View { self }
    public func fixedSize() -> some View { self }
    public func fixedSize(horizontal: Bool, vertical: Bool) -> some View { self }
    public func layoutPriority(_ p: Double) -> some View { self }
    public func aspectRatio(_ r: CGFloat? = nil, contentMode: ContentMode) -> some View { self }
    public func scaledToFit() -> some View { self }
    public func scaledToFill() -> some View { self }
    public func background<V: View>(_ v: V, alignment: Alignment = .center) -> some View { self }
    public func background<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { self }
    public func background<S: ShapeStyle, T: Shape>(_ s: S, in shape: T) -> some View { self }
    public func overlay<V: View>(_ v: V, alignment: Alignment = .center) -> some View { self }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { self }
    public func clipShape<S: Shape>(_ s: S) -> some View { self }
    public func contentShape<S: Shape>(_ s: S) -> some View { self }
    public func cornerRadius(_ r: CGFloat) -> some View { self }
    public func shadow(color: Color = .black, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    public func opacity(_ o: Double) -> some View { self }
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View { self }
    public func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> some View { self }
    public func rotationEffect(_ a: Angle, anchor: UnitPoint = .center) -> some View { self }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    public func offset(_ s: CGSize) -> some View { self }
    public func position(x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    public func position(_ p: CGPoint) -> some View { self }
    public func zIndex(_ z: Double) -> some View { self }
    public func allowsHitTesting(_ b: Bool) -> some View { self }
    public func disabled(_ b: Bool) -> some View { self }
    public func hidden() -> some View { self }
    public func blur(radius: CGFloat) -> some View { self }
    public func compositingGroup() -> some View { self }
    public func drawingGroup() -> some View { self }
    public func animation<V: Equatable>(_ a: Animation?, value: V) -> some View { self }
    public func transition(_ t: AnyTransition) -> some View { self }
    public func id<ID: Hashable>(_ id: ID) -> some View { self }
    public func onAppear(perform: (() -> Void)? = nil) -> some View { self }
    public func onDisappear(perform: (() -> Void)? = nil) -> some View { self }
    public func onTapGesture(count: Int = 1, perform: @escaping () -> Void) -> some View { self }
    public func onChange<V: Equatable>(of v: V, _ action: @escaping (V, V) -> Void) -> some View { self }
    public func onChange<V: Equatable>(of v: V, _ action: @escaping () -> Void) -> some View { self }
    public func task(_ action: @escaping @Sendable () async -> Void) -> some View { self }
    public func gesture(_ g: DragGesture) -> some View { self }
    public func simultaneousGesture(_ g: DragGesture) -> some View { self }
    public func buttonStyle<S: PrimitiveButtonStyle>(_ s: S) -> some View { self }
    public func buttonStyle<S: ButtonStyle>(_ s: S) -> some View { self }
    public func ignoresSafeArea(_ regions: Int = 0, edges: Edge.Set = .all) -> some View { self }
    public func environmentObject<O: ObservableObject>(_ o: O) -> some View { self }
    public func statusBarHidden(_ h: Bool = true) -> some View { self }
    public func persistentSystemOverlays(_ v: Visibility) -> some View { self }
    public func preferredColorScheme(_ s: ColorScheme?) -> some View { self }
    public func accessibilityLabel(_ s: String) -> some View { self }
    public func accessibilityHidden(_ b: Bool) -> some View { self }
    public func sheet<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View { self }
    public func fullScreenCover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View { self }
    public func contentTransition(_ t: ContentTransition) -> some View { self }
    public func safeAreaPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { self }
    public func mask<M: View>(_ m: M) -> some View { self }
    public func blendMode(_ m: BlendMode) -> some View { self }
    public func rotation3DEffect(_ a: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint = .center, perspective: CGFloat = 1) -> some View { self }
}
extension Text { public enum Case { case uppercase, lowercase } }
public struct ContentTransition { public static let numericText = ContentTransition() ; public static func numericText(countsDown: Bool = false) -> ContentTransition { ContentTransition() } ; public static let identity = ContentTransition(), opacity = ContentTransition() }
public enum BlendMode { case normal, multiply, screen, plusLighter }

// MARK: UIKit bridging
public protocol UIViewRepresentable: View where Body == Never {
    associatedtype UIViewType: UIView
    typealias Context = UIViewRepresentableContext<Self>
    func makeUIView(context: Context) -> UIViewType
    func updateUIView(_ uiView: UIViewType, context: Context)
}
extension UIViewRepresentable { public var body: Never { fatalError() } }
public struct UIViewRepresentableContext<R> {}

// MARK: App
@MainActor public protocol App {
    associatedtype Body: Scene
    init()
    @SceneBuilder var body: Body { get }
}
extension App { public static func main() {} }
public protocol Scene {}
@resultBuilder public struct SceneBuilder { public static func buildBlock<S: Scene>(_ s: S) -> S { s } }
public struct WindowGroup<Content: View>: Scene { public init(@ViewBuilder content: () -> Content) {} }
