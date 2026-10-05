import unittest

from select_apple_simulator import eligible_ids, select_device


A = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
B = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
C = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"


def destinations(*identifiers, ineligible=()):
    return ('Available destinations for the "PatrickCompanion" scheme:\n'
            + "\n".join(f"{{ platform:iOS Simulator, arch:arm64, id:{value}, OS:26.5, name:iPhone 17 }}" for value in identifiers)
            + '\nIneligible destinations for the "PatrickCompanion" scheme:\n'
            + "\n".join(f"{{ platform:iOS Simulator, id:{value}, name:iPhone 17, error:runtime unavailable }}" for value in ineligible))


def phone(identifier, **overrides):
    return {"udid": identifier, "name": "iPhone 17", "isAvailable": True, "state": "Shutdown", **overrides}


class SimulatorSelectionChecks(unittest.TestCase):
    def test_newest_version_is_numeric(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-9": [phone(A)],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-10": [phone(B)],
        }}
        self.assertEqual(select_device(devices, destinations(A, B))[0], B)

    def test_booted_compatible_device_avoids_extra_boot(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [phone(A, state="Booted")],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [phone(B)],
        }}
        self.assertEqual(select_device(devices, destinations(A, B))[0], A)

    def test_only_installed_available_phone_and_eligible_ids(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [phone(A, isAvailable=False), phone(B, name="iPad Pro"), phone(C)],
            "com.apple.CoreSimulator.SimRuntime.watchOS-26-5": [phone(A)],
        }}
        self.assertEqual(select_device(devices, destinations(A, B, C))[0], C)

    def test_ineligible_xcode_destination_is_not_selected(self):
        devices = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [phone(A)]}}
        with self.assertRaisesRegex(ValueError, "No runtime was downloaded"):
            select_device(devices, destinations(ineligible=[A]))

    def test_missing_runtime_fails_explicitly(self):
        with self.assertRaisesRegex(ValueError, "No installed, available iPhone"):
            select_device({"devices": {}}, destinations(A))

    def test_generic_destination_and_format_drift_fail_closed(self):
        self.assertEqual(eligible_ids("{ platform:iOS Simulator, id:" + A + " }"), set())
        self.assertEqual(eligible_ids('Available destinations for the "PatrickCompanion" scheme:\n'
                                     '{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }'), set())


if __name__ == "__main__":
    unittest.main()
