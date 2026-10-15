import AppKit
import Darwin
import Foundation
import Testing
import BoardKit
@testable import CanvasKit

/// The performance budgets of DESIGN.md §11, measured on a real canvas in an offscreen
/// window. They only mean something in an optimized build, so they run when `EB_PERF` is set:
///
///     EB_PERF=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceTests
///
/// Each check prints a `BUDGET|name|measured|budget|result` line that CI gathers into a table.
enum Budget {
    static let enabled = ProcessInfo.processInfo.environment["EB_PERF"] != nil

    static func check(
        _ name: String, _ measured: Double, under budget: Double, unit: String = "ms",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let pass = measured <= budget
        print("BUDGET|\(name)|\(String(format: "%.2f", measured)) \(unit)|< \(budget.formatted()) \(unit)|\(pass ? "pass" : "FAIL")")
        #expect(pass, "\(name): \(measured) \(unit), budget \(budget) \(unit)", sourceLocation: sourceLocation)
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// The value below which `fraction` of the samples fall.
    static func percentile(_ samples: [Double], _ fraction: Double) -> Double {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(Int((Double(sorted.count) * fraction).rounded(.up)) - 1, sorted.count - 1)]
    }

    /// The process's memory footprint, as Activity Monitor shows it.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(task_self_trap(), task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .infinity
    }
}

/// Generated boards for the budgets.
@MainActor
enum PerfBoards {
    static let stamp = Date(timeIntervalSince1970: 1_800_000_000)
    static let sentences = [
        "Ferry left **11 minutes early** on the 3rd. Who changed the schedule?",
        "Night guard says the gate was *already open* when he arrived.",
        "Check the harbor logs for `23:41` and the second boat.",
        "Insurance claim filed two days before the storm, by a shell company.",
    ]
    static let palette = LinkPalette(vibrant: "#3A7BFF", muted: "#5C6A88", darkVibrant: "#12306E", darkMuted: "#1B2235", light: "#E8EEFF")

    /// Twenty distinct photos, 1600 px on the long side.
    static let photos: [ImportedImage] = (0..<20).compactMap { TestPhotos.make(index: $0) }

    /// `count` cards in a grid: 3 in 10 text, 4 in 10 photos, 3 in 10 web cards with
    /// snapshots, and `strings` strings between neighbors.
    static func board(cards count: Int, strings stringCount: Int, columns: Int = 25) -> Board {
        var board = Board.new(title: "Budget", now: stamp)
        for photo in photos { board.assets[photo.id] = photo.asset }
        board.cards = (0..<count).map { index in
            let frame = Rect(x: Double(index % columns) * 420, y: Double(index / columns) * 340, width: 300, height: 220)
            let content: CardContent
            switch index % 10 {
            case 0...2:
                content = .text(TextPayload(content: sentences[index % sentences.count]))
            case 3...6:
                content = .image(ImagePayload(asset: photos[index % photos.count].id, caption: index % 2 == 0 ? "Exhibit \(index)" : nil))
            default:
                var web = WebPayload(url: URL(string: "https://example.com/story/\(index)")!)
                web.snapshot = LinkSnapshot(
                    fetchedAt: stamp, variant: [LinkVariant.hero, .article, .compact][index % 3],
                    title: "Harbor authority releases night logs, part \(index)",
                    pageDescription: "The logs show three unscheduled departures in the week before the storm.",
                    siteName: "Example News", author: "J. Rivera", publishedAt: stamp,
                    image: index % 3 == 2 ? nil : photos[index % photos.count].id, palette: palette
                )
                content = .web(web)
            }
            return Card(frame: frame, z: index, createdAt: stamp, modifiedAt: stamp, content: content)
        }
        var strings: [BoardString] = []
        var index = 0
        while strings.count < stringCount, count > 1 {
            let from = board.cards[index % count].id
            let to = board.cards[(index + (index % 2 == 0 ? 1 : columns)) % count].id
            if from != to { strings.append(BoardString(from: from, to: to, label: index % 5 == 0 ? "same night" : nil)) }
            index += 1
        }
        board.strings = strings
        return board
    }

    /// A canvas showing `board` in an offscreen 1440 × 900 window.
    static func canvas(for board: Board) -> (BoardCanvasView, NSWindow, BoardStore) {
        _ = NSApplication.shared
        let store = BoardStore(board: board)
        let view = BoardCanvasView(store: store, appearance: TextCardTests.appearance)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        // Swift owns the window; closing it must not release it a second time.
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return (view, window, store)
    }

    /// Lets queued main-actor work (image decodes coming back) run.
    static func settle(_ seconds: Double = 0.05) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

@MainActor
@Suite("Performance budgets", .enabled(if: Budget.enabled), .serialized)
struct PerformanceTests {
    /// One frame: move the camera, then draw for the frame's slice.
    func frame(_ view: BoardCanvasView, _ camera: Camera) -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        view.setCamera(camera)
        view.renderQueue.runSlice()
        return Budget.milliseconds(clock.now - start)
    }

    func pan(_ view: BoardCanvasView, around center: CGPoint, radius: CGFloat, zoom: CGFloat, frames: Int) -> [Double] {
        (0..<frames).map { step in
            let angle = CGFloat(step) / CGFloat(frames) * 2 * .pi
            return frame(view, Camera(center: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius), zoom: zoom))
        }
    }

    func zoomSweep(_ view: BoardCanvasView, center: CGPoint, from low: CGFloat, to high: CGFloat, frames: Int) -> [Double] {
        (0..<frames).map { step in
            let t = CGFloat(step) / CGFloat(frames - 1)
            let wave = (1 - cos(t * 2 * .pi)) / 2
            return frame(view, Camera(center: center, zoom: low * pow(high / low, wave)))
        }
    }

    @Test func panAndZoom500Cards() async {
        let board = PerfBoards.board(cards: 500, strings: 300)
        let (view, window, _) = PerfBoards.canvas(for: board)
        defer { window.close() }
        let center = CGPoint(x: 5000, y: 3000)
        // Warm up: bring cards into view and let their first decodes come back.
        _ = pan(view, around: center, radius: 1800, zoom: 0.6, frames: 60)
        await PerfBoards.settle(0.5)

        let panning = pan(view, around: center, radius: 1800, zoom: 0.6, frames: 240)
        Budget.check("Pan, 500 cards (p95 frame)", Budget.percentile(panning, 0.95), under: 4)
        let zooming = zoomSweep(view, center: center, from: 0.2, to: 1.5, frames: 240)
        Budget.check("Zoom, 500 cards (p95 frame)", Budget.percentile(zooming, 0.95), under: 4)
    }

    @Test func panAndZoom3000Cards() async {
        let board = PerfBoards.board(cards: 3000, strings: 1000, columns: 60)
        let (view, window, _) = PerfBoards.canvas(for: board)
        defer { window.close() }
        let center = CGPoint(x: 12_600, y: 8_500)
        _ = pan(view, around: center, radius: 3000, zoom: 0.1, frames: 60)
        await PerfBoards.settle(0.3)

        let far = pan(view, around: center, radius: 3000, zoom: 0.08, frames: 180)
        Budget.check("Pan, 3,000 cards, whole board in view (p95 frame)", Budget.percentile(far, 0.95), under: 16.7)
        let mid = pan(view, around: center, radius: 3000, zoom: 0.3, frames: 180)
        Budget.check("Pan, 3,000 cards at 30% (p95 frame)", Budget.percentile(mid, 0.95), under: 16.7)
        let zooming = zoomSweep(view, center: center, from: 0.06, to: 1, frames: 180)
        Budget.check("Zoom, 3,000 cards (p95 frame)", Budget.percentile(zooming, 0.95), under: 16.7)
    }

    @Test func drag50CardsWith200Strings() {
        // 50 cards in a cluster, each tied to four others.
        var board = PerfBoards.board(cards: 200, strings: 0, columns: 20)
        let cluster = (0..<50).map { board.cards[($0 / 10) * 20 + $0 % 10].id }
        board.strings = (0..<200).map { index in
            BoardString(from: cluster[index % 50], to: board.cards[(index * 7 + 3) % 200].id)
        }.filter { $0.from != $0.to }
        let (view, window, store) = PerfBoards.canvas(for: board)
        defer { window.close() }
        view.setCamera(Camera(center: CGPoint(x: 1500, y: 800), zoom: 0.5))
        view.select(Set(cluster))

        let grab = store.card(cluster[0])!.frame
        let start = CGPoint(x: grab.x + 150, y: grab.y + 150)
        func event(_ type: NSEvent.EventType, _ world: CGPoint) -> NSEvent {
            let point = view.convert(view.camera.worldToView(world, in: view.bounds.size), to: nil)
            return NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!
        }
        view.mouseDown(with: event(.leftMouseDown, start))
        let clock = ContinuousClock()
        var samples: [Double] = []
        for step in 1...240 {
            let point = CGPoint(x: start.x + CGFloat(step) * 3, y: start.y + sin(CGFloat(step) / 20) * 120)
            let began = clock.now
            view.mouseDragged(with: event(.leftMouseDragged, point))
            if step > 10 { samples.append(Budget.milliseconds(clock.now - began)) }
        }
        view.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x + 720, y: start.y)))
        #expect(store.card(cluster[0])!.frame.x > grab.x + 600)
        Budget.check("Drag 50 cards with 200 strings (p95 frame)", Budget.percentile(samples, 0.95), under: 8.3)
    }

    @Test func openA50MBBoard() async throws {
        // 300 cards, 100 of them photos, each with its own ~500 KB image.
        let noise = try #require(Self.noiseJPEG())
        var board = PerfBoards.board(cards: 300, strings: 150, columns: 20)
        board.assets = [:]
        var photoIndex = 0
        for index in board.cards.indices {
            guard case .image(var photo) = board.cards[index].content else {
                if case .web(var web) = board.cards[index].content {
                    web.snapshot?.image = nil
                    board.cards[index].content = .web(web)
                }
                continue
            }
            guard photoIndex < 100 else {
                board.cards[index].content = .text(TextPayload(content: "Photo pending"))
                continue
            }
            var bytes = noise
            bytes.append(contentsOf: withUnsafeBytes(of: UInt32(photoIndex)) { Array($0) })
            let asset = Asset(mime: "image/jpeg", pixelWidth: 1400, pixelHeight: 1050, data: bytes)
            let id = "sha256-perf-\(photoIndex)"
            board.assets[id] = asset
            photo.asset = id
            board.cards[index].content = .image(photo)
            photoIndex += 1
        }
        let data = try BoardCodec.encode(board)
        print("BUDGET-INFO|board size|\(data.count / 1_048_576) MB, \(board.cards.count) cards, \(board.assets.count) photos")
        #expect(data.count > 45_000_000)

        _ = NSApplication.shared
        let clock = ContinuousClock()
        let start = clock.now
        let loaded = try BoardCodec.decode(data).board
        let store = BoardStore(board: loaded)
        let view = BoardCanvasView(store: store, appearance: TextCardTests.appearance)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        // Swift owns the window; closing it must not release it a second time.
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.setCamera(Camera(center: CGPoint(x: 1600, y: 700), zoom: 0.5))
        view.renderQueue.runSlice()
        Budget.check("Open 50 MB board: first frame", Budget.milliseconds(clock.now - start), under: 800)

        // Every photo in view (not just nearby) has its picture.
        let visibleRect = view.camera.visibleWorldRect(in: view.bounds.size)
        let onScreen = store.board.cards.filter {
            if case .image = $0.content { return CanvasGeometry.boundingBox(of: $0).intersects(visibleRect) }
            return false
        }.map(\.id)
        #expect(!onScreen.isEmpty)
        while !onScreen.allSatisfy({ view.cardNodes[$0]?.fullImage != nil }), clock.now - start < .seconds(5) {
            await PerfBoards.settle(0.01)
        }
        Budget.check("Open 50 MB board: visible photos decoded", Budget.milliseconds(clock.now - start), under: 1500)
    }

    @Test func memoryAndIdleAtRest() async {
        let board = PerfBoards.board(cards: 500, strings: 300)
        let (view, window, _) = PerfBoards.canvas(for: board)
        defer { window.close() }
        // Visit the whole board once, close up, so every kind of bitmap has been made.
        for row in 0..<4 {
            for column in 0..<5 {
                view.setCamera(Camera(center: CGPoint(x: 1000 + Double(column) * 2100, y: 800 + Double(row) * 1700), zoom: 0.8))
                while !view.renderQueue.isEmpty { view.renderQueue.runSlice() }
                await PerfBoards.settle(0.1)
            }
        }
        view.setCamera(Camera(center: CGPoint(x: 5000, y: 3000), zoom: 0.6))
        while !view.renderQueue.isEmpty { view.renderQueue.runSlice() }
        await PerfBoards.settle(1)
        Budget.check("Memory, 500-card board at rest", Budget.footprintMB(), under: 450, unit: "MB")

        // At rest nothing is scheduled to run: no display links, physics, pulses or fetches.
        await PerfBoards.settle(0.3)
        let busy = [
            view.animationLink != nil, view.physics.isRunning, !view.renderQueue.isEmpty,
            !view.previewTasks.isEmpty, view.isPulsing,
        ].filter { $0 }.count
        Budget.check("Work scheduled at rest (timers, links, fetches)", Double(busy), under: 0, unit: "items")
    }

    /// A 1400 × 1050 JPEG of noise, about half a megabyte: photos that don't compress.
    static func noiseJPEG() -> Data? {
        let width = 1400, height = 1050
        var random = SplitMix(seed: 42)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = random.next()
            pixels[index] = UInt8(truncatingIfNeeded: value)
            pixels[index + 1] = UInt8(truncatingIfNeeded: value >> 8)
            pixels[index + 2] = UInt8(truncatingIfNeeded: value >> 16)
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ),
              let encoded = try? ImageImporter.encode(image, opaque: true) else { return nil }
        return encoded.asset.decodedData()
    }
}
