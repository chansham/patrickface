import Foundation
import AVFoundation
import Combine
import ImageIO
import SwiftUI

enum PatrickExperienceResources {
    static func layouts(bundle: Bundle = .main) -> [PatrickFaceLayoutSpec] {
        guard let url = url("layouts.json", bundle: bundle), let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(PatrickFaceLayoutCatalog.self, from: data), value.isValid else { return [.classic] }
        return value.layouts
    }
    static func calendar(bundle: Bundle = .main) -> PatrickCelebrationCalendar? {
        guard let url = url("calendar.json", bundle: bundle), let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(PatrickCelebrationCalendar.self, from: data), value.schemaVersion == 1 else { return nil }
        return value
    }
    static func url(_ path: String, bundle: Bundle = .main) -> URL? {
        var relative = path
        if relative.hasPrefix("experience/") { relative.removeFirst("experience/".count) }
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.contains(":"), !relative.contains("\\"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let root = bundle.resourceURL?.appendingPathComponent("Experience") else { return nil }
        let result = root.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: result.path) ? result : nil
    }
    static func catalog(bundle: Bundle = .main) -> PatrickOutfitCatalog? {
        guard let url = url("themes.json", bundle: bundle), let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(PatrickOutfitCatalog.self, from: data), catalog.schemaVersion == 1 else { return nil }
        return catalog
    }
    static func outfits(bundle: Bundle = .main) -> [PatrickOutfitCatalog.Outfit] { catalog(bundle: bundle)?.outfits ?? [] }
    static func outfit(_ settings: PatrickExperienceSettings, scene: String, from outfits: [PatrickOutfitCatalog.Outfit], soundOutfitID: String? = nil) -> PatrickOutfitCatalog.Outfit? {
        if settings.outfitID != "auto" { return outfits.first { $0.id == settings.outfitID } }
        if let soundOutfitID, let value = outfits.first(where: { $0.id == soundOutfitID }) { return value }
        if let id = catalog()?.defaultSceneOutfits?[scene], let value = outfits.first(where: { $0.id == id }) { return value }
        return outfits.first { $0.scene == scene && $0.id != "auto" }
            ?? outfits.first { $0.scene == "awake" && $0.id != "auto" }
            ?? outfits.first { $0.id != "auto" }
    }
    static func eventClips(_ settings: PatrickExperienceSettings, outfit: PatrickOutfitCatalog.Outfit?, from outfits: [PatrickOutfitCatalog.Outfit]) -> [String: String] {
        var result = outfit?.actionClips ?? [:]
        if settings.outfitID == "auto" {
            for (event, outfitID) in catalog()?.defaultActionOutfits ?? [:] {
                if let clip = outfits.first(where: { $0.id == outfitID })?.actionClips[event] { result[event] = clip }
            }
        }
        return result
    }
}

struct PatrickSchedulePreferences: View {
    @Binding var settings: PatrickExperienceSettings
    var body: some View {
        Section("作息與紀念日") {
            DatePicker("睡前開始", selection: sleepTime(start: true), displayedComponents: .hourAndMinute)
            DatePicker("早晨開始", selection: sleepTime(start: false), displayedComponents: .hourAndMinute)
            Text("自動情境使用這段時段；開始與結束相同就停用定時睡前。").font(.footnote)
            Toggle("生日小表演", isOn: Binding(get: { settings.birthdayMMDD != nil }, set: { settings.birthdayMMDD = $0 ? "01-01" : nil }))
            if settings.birthdayMMDD != nil {
                Picker("生日月份", selection: birthdayPart(month: true)) { ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) } }
                Picker("生日日期", selection: birthdayPart(month: false)) { ForEach(1...daysInMonth, id: \.self) { Text("\($0)日").tag($0) } }
            }
            Toggle("已收錄的節日", isOn: Binding(get: { settings.holidaysEnabled ?? true }, set: { settings.holidaysEnabled = $0 }))
            Picker("睡前倒數提醒", selection: Binding(get: { settings.quietAlerts }, set: { settings.quietAlerts = $0 })) {
                Text("靜音，鬧鐘除外").tag(PatrickQuietAlerts.silentExceptAlarms)
                Text("照常出聲").tag(PatrickQuietAlerts.allowSound)
                Text("不送出，鬧鐘除外").tag(PatrickQuietAlerts.hideExceptAlarms)
            }
            Text("預設在睡前時段或睡前情境保持安靜。會議、通勤、專注和運動中，倒數也不出聲。").font(.footnote)
            Text("香港公眾假期（1823，2026–2027）不是工作日。生日只存月日。").font(.footnote)
            TextField("派大星叫你", text: Binding(get: { settings.greetingDisplayName }, set: { settings.greetingName = $0 }))
            Toggle("用語音叫名字", isOn: Binding(get: { settings.voiceGreetingOn }, set: { settings.voiceGreetingEnabled = $0 }))
            Text("預設只顯示「派大星叫你 \(settings.greetingDisplayName)」，不朗讀。").font(.footnote)
            Stepper("一天主動震動 \(settings.dailyHapticBudget) 次", value: Binding(get: { settings.dailyHapticBudget }, set: { settings.proactiveHapticBudget = $0 }), in: 0...24)
            Toggle("表情跟著今天", isOn: Binding(get: { settings.moodFollowsDayOn }, set: { settings.moodFollowsDay = $0 }))
            Toggle("平日早晨叫我", isOn: Binding(get: { settings.wakeAlarmOn }, set: { settings.wakeAlarmEnabled = $0 }))
            Toggle("假日和周末不叫", isOn: Binding(get: { settings.skipsWakeOnRestDays }, set: { settings.skipWakeOnRestDays = $0 }))
            Text("早晨鬧鐘預設關掉。香港公眾假期和周末不叫；你自己開始的午睡仍會響。手機鈴聲仍預設關掉。").font(.footnote).fixedSize(horizontal: false, vertical: true)
            Toggle("起床時手機也響", isOn: Binding(get: { settings.phoneWakeFallback }, set: { settings.phoneWakeFallbackEnabled = $0 }))
            Text("手錶戴著時由手錶叫醒。手機只在這項打開、而且手錶不在手上時才出聲。").font(.footnote).fixedSize(horizontal: false, vertical: true)
            Toggle("前景聽一下周圍", isOn: Binding(get: { settings.soundTheaterOn }, set: { settings.soundTheaterEnabled = $0 ? true : nil }))
            Text("只在 App 開著時聽幾秒，分辨下雨、煮東西或唱歌。沒有全天麥克風。關掉就不聽。").font(.footnote).fixedSize(horizontal: false, vertical: true)
            TextField("家的緯度", text: coordinate(\.homeLatitude))
            TextField("家的經度", text: coordinate(\.homeLongitude))
            Text("回家後可以說「我回來了」。填了家的位置，也只在 App 開著時試著知道你到家，不會申請永遠定位。").font(.footnote).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var birthday: [Int] { (settings.birthdayMMDD ?? "01-01").split(separator: "-").compactMap { Int($0) } }
    private var month: Int { birthday.count == 2 ? min(12, max(1, birthday[0])) : 1 }
    private var day: Int { birthday.count == 2 ? min(31, max(1, birthday[1])) : 1 }
    private var daysInMonth: Int { Self.days(month) }
    private static func days(_ month: Int) -> Int { [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] }
    private func birthdayPart(month isMonth: Bool) -> Binding<Int> {
        Binding(get: { isMonth ? month : day }, set: { value in
            let m = isMonth ? value : month, d = min(isMonth ? day : value, Self.days(isMonth ? value : month))
            settings.birthdayMMDD = String(format: "%02d-%02d", m, d)
        })
    }
    private func coordinate(_ keyPath: WritableKeyPath<PatrickExperienceSettings, Double?>) -> Binding<String> {
        Binding(get: { $settings.wrappedValue[keyPath: keyPath].map { String($0) } ?? "" }, set: { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            $settings.wrappedValue[keyPath: keyPath] = trimmed.isEmpty ? nil : Double(trimmed)
        })
    }
    private func sleepTime(start: Bool) -> Binding<Date> {
        Binding(get: {
            let minutes = start ? settings.sleepStart : settings.sleepEnd
            return Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(minutes) * 60)
        }, set: { date in
            let value = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
            if start { settings.sleepStartMinutes = value } else { settings.sleepEndMinutes = value }
        })
    }
}

/// Short local cues only. Nothing keeps audio or animation alive in background.
@MainActor
final class PatrickFeedback: ObservableObject {
    private var player: AVAudioPlayer?
    func stop() { player?.stop(); player = nil }

    func play(_ event: String, settings: PatrickExperienceSettings, active: Bool) {
        guard active else { return }
        guard settings.soundEnabled else { return }
        // Manifest mapping is optional; a missing cue is silent, never network audio.
        guard let url = PatrickExperienceResources.url("audio/manifest.json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let cue = event == "celebrate" ? "complete" : (["pet", "feed", "wake", "bubble"].contains(event) ? event : "softclick")
        let entries = manifest["cues"] as? [[String: Any]] ?? []
        guard let entry = entries.first(where: { $0["id"] as? String == cue }),
              let path = entry["path"] as? String, let sound = PatrickExperienceResources.url(path) else { return }
        do {
            stop()
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            #endif
            player = try AVAudioPlayer(contentsOf: sound)
            player?.volume = Float(entry["gain"] as? Double ?? 0.35)
            player?.play()
        } catch { stop() }
    }
}


/// One shared manifest controls both apps and the web preview; transforms are whole-clip.
struct PatrickFaceLayoutCatalog: Decodable {
    let schemaVersion: Int
    let coordinateSize: [Double]
    let layouts: [PatrickFaceLayoutSpec]
    var isValid: Bool {
        schemaVersion == 1 && coordinateSize == [832, 992]
            && Set(layouts.map(\.id)) == Set(["classic", "bold", "theater", "activity"])
            && layouts.count == 4 && layouts.allSatisfy(\.isValid)
    }
}
struct PatrickFaceLayoutSpec: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String
    let characterTransform: [Double]
    let timeCenter: [Double]
    let timeFontSize: Double
    let dateCenter: [Double]
    let dateFontSize: Double
    let informationRect: [Double]?
    var isValid: Bool {
        characterTransform.count == 3 && characterTransform.allSatisfy(\.isFinite)
            && characterTransform[0] > 0 && characterTransform[0] <= 1
            && timeCenter.count == 2 && timeCenter.allSatisfy(\.isFinite)
            && dateCenter.count == 2 && dateCenter.allSatisfy(\.isFinite)
            && (80...180).contains(timeFontSize) && (20...40).contains(dateFontSize)
            && (informationRect == nil || (informationRect!.count == 4 && informationRect!.allSatisfy(\.isFinite)))
    }
    static let classic = PatrickFaceLayoutSpec(id: "classic", title: "經典陪伴", description: "上方看時間，中央看角色。",
        characterTransform: [1, 0, 0], timeCenter: [416, 109], timeFontSize: 108,
        dateCenter: [416, 205], dateFontSize: 28, informationRect: nil)
    static let available = PatrickExperienceResources.layouts()
    static func resolve(_ id: String) -> PatrickFaceLayoutSpec { available.first { $0.id == id } ?? .classic }
    static func presentationID(_ settings: PatrickExperienceSettings) -> String {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--patrick-preview-layout"), arguments.indices.contains(index + 1),
           ["classic", "bold", "theater", "activity"].contains(arguments[index + 1]) { return arguments[index + 1] }
        #endif
        return settings.effectiveLayoutID
    }
}
struct PatrickLayoutPicker: View {
    @Binding var settings: PatrickExperienceSettings
    var body: some View {
        Picker("錶面版式", selection: Binding(get: { settings.effectiveLayoutID }, set: { settings.layoutID = $0 })) {
            ForEach(PatrickFaceLayoutSpec.available) { Text($0.title).tag($0.id) }
        }
        Text(PatrickFaceLayoutSpec.resolve(settings.effectiveLayoutID).description).font(.footnote).foregroundStyle(.secondary)
    }
}

/// Numeric clock always has its own timeline, even if an animation cannot load.
/// The image, hand rig and anchor all receive the SAME layout transform.
@MainActor struct PatrickLayoutFace: View {
    @ObservedObject var player: PatrickAnimationPlayer
    @ObservedObject var artwork: PatrickClockArtwork
    let experience: PatrickExperienceState
    var dimmed = false
    var active = true
    var notice: String? = nil
    private var layout: PatrickFaceLayoutSpec { .resolve(PatrickFaceLayoutSpec.presentationID(experience.settings)) }
    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width / 832, geometry.size.height / 992)
            let width = 832 * unit, height = 992 * unit
            ZStack(alignment: .topLeading) {
                character(unit: unit)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .scaleEffect(CGFloat(layout.characterTransform[0]), anchor: .topLeading)
                    .offset(x: layout.characterTransform[1] * unit, y: layout.characterTransform[2] * unit)
                digitalClock(unit: unit)
                if let rect = layout.informationRect {
                    PatrickLayoutActivity(experience: experience, active: active && !dimmed, unit: unit, notice: notice)
                        .frame(width: rect[2] * unit, height: rect[3] * unit)
                        .position(x: (rect[0] + rect[2] / 2) * unit, y: (rect[1] + rect[3] / 2) * unit)
                }
            }
            .frame(width: width, height: height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
    @ViewBuilder private func character(unit: CGFloat) -> some View {
        if experience.settings.faceMode == .arms && artwork.manifest != nil && !player.isPlaying {
            PatrickOrganicClock(artwork: artwork, dimmed: dimmed).frame(width: 832 * unit, height: 992 * unit)
        } else if let image = player.image {
            let side = 665.6 * unit
            let w = side * CGFloat(min(1, player.cellAspectRatio) * player.drawingScale)
            let h = side * CGFloat(min(1, 1 / player.cellAspectRatio) * player.drawingScale)
            Image(decorative: image, scale: 1).resizable().interpolation(.high)
                .frame(width: w, height: h)
                .position(x: 83.2 * unit + side * CGFloat(player.masterAnchor[0]) + w * CGFloat(0.5 - player.anchor[0]),
                          y: 248 * unit + side * CGFloat(player.masterAnchor[1]) + h * CGFloat(0.5 - player.anchor[1]))
                .opacity(dimmed ? 0.55 : 1)
        } else {
            Text("動作畫稿尚未準備").font(.footnote).foregroundStyle(.secondary)
                .frame(width: 665.6 * unit, height: 665.6 * unit).position(x: 416 * unit, y: 580.8 * unit)
        }
    }
    private func digitalClock(unit: CGFloat) -> some View {
        TimelineView(.everyMinute) { tick in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: tick.date)
            let hour = parts.hour ?? 0, settings = experience.settings
            ZStack(alignment: .topLeading) {
                HStack(alignment: .firstTextBaseline, spacing: 7 * unit) {
                    Text(String(format: "%02d:%02d", settings.use24Hour ? hour : (hour % 12 == 0 ? 12 : hour % 12), parts.minute ?? 0))
                        .font(.system(size: layout.timeFontSize * unit, weight: dimmed ? .light : (layout.id == "bold" ? .semibold : .medium), design: .rounded)).monospacedDigit()
                    if !settings.use24Hour { Text(hour < 12 ? "AM" : "PM").font(.system(size: 24 * unit)) }
                }
                .foregroundStyle(.white.opacity(dimmed ? 0.72 : 1))
                .position(x: layout.timeCenter[0] * unit, y: layout.timeCenter[1] * unit)
                .accessibilityLabel("現在時間")
                if settings.showDate {
                    Text(tick.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                        .font(.system(size: max(8, layout.dateFontSize * unit))).foregroundStyle(.secondary)
                        .position(x: layout.dateCenter[0] * unit, y: layout.dateCenter[1] * unit)
                }
            }.frame(width: 832 * unit, height: 992 * unit)
        }.allowsHitTesting(false)
    }
}

private struct PatrickLayoutActivity: View {
    let experience: PatrickExperienceState
    let active: Bool
    let unit: CGFloat
    let notice: String?
    var body: some View {
        TimelineView(.periodic(from: .now, by: active && experience.activity?.status == .running ? 1 : 60)) { tick in
            let activity = experience.activity
            let seconds = Int(ceil(activity?.remaining(at: tick.date) ?? 0))
            let progress = min(1, max(0, activity.map { 1 - $0.remaining(at: tick.date) / max(1, $0.durationSeconds) } ?? 0))
            VStack(alignment: .leading, spacing: max(2, 10 * unit)) {
                HStack(alignment: .center, spacing: 12 * unit) {
                    VStack(alignment: .leading, spacing: max(1, 5 * unit)) {
                        Text(activity?.kind.title.replacingOccurrences(of: "陪伴", with: "") ?? "陪伴倒數")
                            .font(.system(size: max(8, 42 * unit))).lineLimit(1)
                        Text(notice ?? (activity == nil ? "還沒開始" : activity?.status == .paused ? "已暫停" : activity?.status == .completed ? "這段完成了" : activity?.status == .cancelled ? "已結束" : "一起慢慢來"))
                            .font(.system(size: max(8, 34 * unit))).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(activity == nil ? "—:—" : String(format: "%02d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: max(14, 72 * unit), weight: .medium, design: .rounded))
                        .monospacedDigit().foregroundStyle(.white).minimumScaleFactor(0.8).lineLimit(1)
                }
                GeometryReader { geometry in
                    Capsule().fill(Color.pink.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.pink).frame(width: geometry.size.width * progress)
                        }
                }.frame(height: max(2, 8 * unit))
                    .accessibilityLabel("陪伴倒數進度").accessibilityValue("\(Int(progress * 100))%")
            }.foregroundStyle(.secondary)
                .overlay(alignment: .top) { Rectangle().fill(Color.pink.opacity(0.35)).frame(height: max(0.5, unit)).offset(y: -max(2, 8 * unit)) }
        }.allowsHitTesting(false)
    }
}

/// Simulator-only full-screen comparison. Default launches keep the official face.
enum PatrickSamplePreview {
    static var requested: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--patrick-show-sample")
        #else
        return false
        #endif
    }
}

/// Transparent layers in `sample/star-pyjamas/`, same pixels as the official body canvas.
enum PatrickSampleSlot {
    static let overlayFile = "overlay.png"
    static let nightcapFile = "nightcap.png"
    static let files = [overlayFile, nightcapFile]

    static func image(_ name: String, expectedWidth: Int, expectedHeight: Int, bundle: Bundle = .main) -> CGImage? {
        guard files.contains(name), expectedWidth > 0, expectedHeight > 0, let root = bundle.resourceURL else { return nil }
        let url = root.appendingPathComponent("sample").appendingPathComponent("star-pyjamas").appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == expectedWidth, image.height == expectedHeight else { return nil }
        return image
    }
}

/// Left: official clock body. Right: that same bitmap plus the sample overlay slots.
@MainActor struct PatrickStarPajamasSample: View {
    /// Full-screen comparison for the simulator launch. Embedded sheets stay compact.
    var fillsScreen = false
    @StateObject private var artwork = PatrickClockArtwork()

    var body: some View {
        Group {
            if fillsScreen {
                filled
            } else {
                compact
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("星星睡衣樣本。左邊是正式派大星，右邊是同一幀加上佔位疊圖。正式素材沒有換。")
        .task { artwork.load() }
    }

    /// Scroll-sized comparison. The image row keeps its own height.
    private var compact: some View {
        VStack(spacing: 4) {
            Text("星星睡衣樣本").font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text("左：正式幀　右：同一錨點疊佔位").font(.caption2).lineLimit(2).minimumScaleFactor(0.6)
            Text(fitLine).font(.caption2).lineLimit(1).minimumScaleFactor(0.5)
            HStack(alignment: .top, spacing: 4) {
                pane(title: "現有", names: [])
                pane(title: "佔位疊圖", names: PatrickSampleSlot.files)
            }
            Text("正式素材沒有換。").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(4)
        .frame(maxWidth: .infinity)
    }

    /// Both frames share the middle of the screen. A top-aligned 896-point image
    /// is clipped off the round watch, so each square is sized from the safe area.
    private var filled: some View {
        GeometryReader { geo in
            let side = max(44, min((geo.size.width - 8) / 2, geo.size.height - 72))
            VStack(spacing: 2) {
                Text("星星睡衣樣本").font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5)
                HStack(alignment: .top, spacing: 4) {
                    pane(title: "現有", names: [], square: side)
                    pane(title: "佔位疊圖", names: PatrickSampleSlot.files, square: side)
                }
                Text(fitLine).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.4)
                Text("正式素材沒有換。").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var bodyImage: CGImage? {
        guard let manifest = artwork.manifest, artwork.images.indices.contains(manifest.body.regionIndex) else { return nil }
        return artwork.images[manifest.body.regionIndex]
    }

    private var fitLine: String {
        guard let canvas = artwork.manifest?.canvas, canvas.anchorPixels.count == 2 else { return artwork.message }
        return "畫布 \(canvas.width)×\(canvas.height)，錨點 \(canvas.anchorPixels[0]),\(canvas.anchorPixels[1])"
    }

    private func pane(title: String, names: [String], square: CGFloat? = nil) -> some View {
        let base = bodyImage
        let layers = sampleLayers(base: base, names: names)
        let missing = base == nil ? [String]() : names.filter { sampleLayers(base: base, names: [$0]).isEmpty }
        return VStack(spacing: 2) {
            Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
            ZStack {
                Color.black
                if let base {
                    Image(decorative: base, scale: 1).resizable().interpolation(.high).scaledToFit()
                }
                ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                    Image(decorative: layer, scale: 1).resizable().interpolation(.high).scaledToFit()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(width: square, height: square)
            if !missing.isEmpty {
                Text(missing.joined(separator: " ")).font(.caption2).foregroundStyle(.red).lineLimit(2).minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sampleLayers(base: CGImage?, names: [String]) -> [CGImage] {
        guard let base else { return [] }
        return names.compactMap { PatrickSampleSlot.image($0, expectedWidth: base.width, expectedHeight: base.height) }
    }
}
