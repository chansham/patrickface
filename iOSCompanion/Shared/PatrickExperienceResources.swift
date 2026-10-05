import Foundation
import AVFoundation
import Combine
import SwiftUI
#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

enum PatrickExperienceResources {
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
    static func outfit(_ settings: PatrickExperienceSettings, scene: String, from outfits: [PatrickOutfitCatalog.Outfit]) -> PatrickOutfitCatalog.Outfit? {
        if settings.outfitID != "auto" { return outfits.first { $0.id == settings.outfitID } }
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
            Text("生日只存月日；節日依內建確切日期，每天最多一次，靜止時不補演。").font(.footnote)
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
        if settings.hapticsEnabled {
            #if os(watchOS)
            WKInterfaceDevice.current().play(event == "celebrate" ? .success : .click)
            #elseif os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
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
