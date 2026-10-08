import Foundation

/// Modern experience timestamps and legacy settings revisions are independent.
/// Resolve them once before either endpoint interprets a legacy sleep command.
enum PatrickSettingsMerge {
    struct Resolution: Equatable {
        var experience: PatrickExperienceState
        var sleepModeRawValue: String
        var acceptsLegacySettings: Bool
        var acceptedIncomingExperience: Bool
        var hasModernExperience: Bool
    }

    static func sleepModeRawValue(for scene: PatrickExperienceScene) -> String {
        switch scene {
        case .sleeping: "on"
        case .awake: "off"
        default: "automatic"
        }
    }

    static func resolve(localExperience: PatrickExperienceState, incomingExperience: PatrickExperienceState?,
                        localRevision: UInt64, incomingRevision: UInt64,
                        localSleepMode: String, incomingSleepMode: String, at date: Date = .now) -> Resolution {
        let acceptsLegacy = incomingRevision >= localRevision
        if let incoming = incomingExperience {
            let acceptsExperience = incoming.isNewer(than: localExperience)
            let experience = acceptsExperience ? incoming : localExperience
            return Resolution(experience: experience,
                              sleepModeRawValue: sleepModeRawValue(for: experience.settings.scene),
                              acceptsLegacySettings: acceptsLegacy,
                              acceptedIncomingExperience: acceptsExperience, hasModernExperience: true)
        }
        // Only a genuinely old payload without experience may map a changed
        // legacy sleep mode into a new scene. A rejected modern payload is not
        // a legacy packet and must never enter this branch.
        var experience = localExperience
        let mode = acceptsLegacy ? incomingSleepMode : localSleepMode
        if acceptsLegacy && mode != localSleepMode {
            let scene: PatrickExperienceScene = mode == "on" ? .sleeping : mode == "off" ? .awake : .automatic
            if experience.settings.scene != scene {
                experience.settings.scene = scene
                experience.changed(at: date)
            }
        }
        return Resolution(experience: experience, sleepModeRawValue: mode,
                          acceptsLegacySettings: acceptsLegacy,
                          acceptedIncomingExperience: false, hasModernExperience: false)
    }
}
