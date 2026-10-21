"""Windows checks for native source contracts and rendered-hand geometry.

This does not compile Swift. The geometry tests read the actual Swift transform
sequence and evaluate its affine operations against independent clock vectors.
Run the separate NativeRulesChecks.swift on a machine with Swift for native rules.
"""

from pathlib import Path
import json
import math
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
FACE = (ROOT / "PatrickFace/PatrickFaceView.swift").read_text(encoding="utf-8")
SHARED = (ROOT / "PatrickFace/PatrickShared.swift").read_text(encoding="utf-8")
APP = (ROOT / "PatrickFace/PatrickFaceApp.swift").read_text(encoding="utf-8")
COMPLICATION = (
    ROOT / "PatrickFaceComplications/PatrickFaceComplications.swift"
).read_text(encoding="utf-8")


def section(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]


def matrix_product(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)]
            for i in range(3)]


def native_hand_matrix(tap_y, slump, tap_scale):
    block = section(FACE, "var rig = scene", "if theme == .clay")
    values = {
        "pose.tapY": tap_y, "pose.slump": slump, "pose.tapScale": tap_scale,
        "Self.clockHub.x": 360.0, "Self.clockHub.y": 498.0,
    }

    def number(expression):
        for key, value in values.items():
            expression = expression.replace(key, repr(value))
        if not re.fullmatch(r"[\d\s.+*()/-]+", expression):
            raise AssertionError(f"Unrecognized transform expression: {expression}")
        return eval(expression, {"__builtins__": {}}, {})

    transform = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    operations = re.findall(r"rig\.(\w+)\(([^\n]+)\)", block)
    if len(operations) != 4:
        raise AssertionError("Hand transform chain changed: review the geometry oracle")
    for operation, arguments in operations:
        match = re.fullmatch(r"x: (.*), y: (.*)", arguments)
        if not match:
            raise AssertionError(f"Unexpected hand transform: {operation}({arguments})")
        x, y = map(number, match.groups())
        if operation == "translateBy":
            next_transform = [[1, 0, x], [0, 1, y], [0, 0, 1]]
        elif operation == "scaleBy":
            next_transform = [[x, 0, 0], [0, y, 0], [0, 0, 1]]
        else:
            raise AssertionError(f"Angle-changing hand transform: {operation}")
        transform = matrix_product(transform, next_transform)
    return transform


class NativeContracts(unittest.TestCase):
    def test_battery_lifecycle_and_unknown_value(self):
        self.assertIn("isBatteryMonitoringEnabled = true", FACE)
        self.assertIn("isBatteryMonitoringEnabled = phase != .background", FACE)
        self.assertIn("isBatteryMonitoringEnabled = false", FACE)
        self.assertIn("level >= 0 && level < 0.2", FACE)
        self.assertNotIn("INFocusStatusCenter", FACE)

    def test_body_animation_cannot_distort_clock_hands(self):
        for start, end in [("private func drawCel", "private func drawToon3D"),
                           ("private func drawToon3D", "private func drawClockHub")]:
            renderer = section(FACE, start, end)
            self.assertIn("body.rotate", renderer)
            self.assertIn("body.scaleBy", renderer)
            self.assertNotIn("rig.rotate", renderer)
            self.assertNotIn("rig.scaleBy", renderer)
            self.assertEqual(renderer.count("context: &rig,"), 3)
            self.assertEqual(renderer.count("pivot: Self.clockHub"), 2)

    def test_rendered_hand_angle_through_actual_swift_transform_chain(self):
        # Include the old failure: low battery + breathing at non-cardinal angles.
        for slump in (0, 1):
            for tap_y, tap_scale in ((0, 1), (-9, 1.045), (-4.5, 1.0225)):
                matrix = native_hand_matrix(tap_y, slump, tap_scale)
                for degrees in range(0, 360, 3):
                    radians = math.radians(degrees)
                    vector = [math.sin(radians), -math.cos(radians)]
                    x = matrix[0][0] * vector[0] + matrix[0][1] * vector[1]
                    y = matrix[1][0] * vector[0] + matrix[1][1] * vector[1]
                    actual = math.degrees(math.atan2(x, -y)) % 360
                    difference = (actual - degrees + 180) % 360 - 180
                    self.assertAlmostEqual(difference, 0, places=10)

    def test_complication_uses_current_experience_and_digital_time(self):
        self.assertIn("PatrickExperienceState.load(from: PatrickSharedStore.defaults)", COMPLICATION)
        self.assertIn("Text(entry.date, style: .time)", COMPLICATION)
        self.assertIn("entry.experience.settings.mood.title", COMPLICATION)
        self.assertNotIn("PatrickComplicationDial", COMPLICATION)
        self.assertIn(".widgetURL(entry.deepLinkURL)", COMPLICATION)

    def test_scenes_are_local_and_preview_is_distinguished(self):
        self.assertIn('sceneKey = "patrick.pet-scene.v1"', APP)
        self.assertIn("isRestoringCompanionState", APP)
        self.assertIn("companion.activate(", APP)
        self.assertIn("if model.previewState != .normal { return .preview }", FACE)
        self.assertIn("physicalCharging: physicalCharging", FACE)
        self.assertIn("reduced || !physicalCharging", FACE)
        self.assertIn("運動陪伴在手錶授權後會寫入健康；沒有授權時仍只是陪伴倒數。", FACE)
        holidays = json.loads((ROOT / "experience" / "hk-public-holidays.json").read_text())
        companion = (ROOT / "iOSCompanion" / "Shared" / "PatrickExperience.swift").read_text()
        self.assertIn("https://www.1823.gov.hk/common/ical/tc.json", holidays["source"])
        self.assertGreaterEqual(len(holidays["holidays"]), 30)
        for row in holidays["holidays"]:
            self.assertIn(row["date"], companion)
            self.assertIn(row["name"], companion)
        self.assertNotIn("import HealthKit", FACE + APP + SHARED)

    def test_heartbeat_does_not_reload_every_minute(self):
        self.assertIn("onChange(of: Calendar.current.component(.minute", FACE)
        self.assertIn("timeIntervalSince(lastComplicationReload) >= 15 * 60", APP)


if __name__ == "__main__":
    unittest.main(verbosity=2)
