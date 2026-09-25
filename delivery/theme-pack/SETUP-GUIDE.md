# Patrick Face theme pack — official-channel setup

This package uses normal Apple-supported paths: Photos/Wallpaper, the Watch app, Shortcuts personal automations, Files, and WidgetKit-capable apps. It does not install a configuration profile, replace a signed app icon, replace an Apple system sound, or install a third-party system watch face.

## 1. Copy the package to iPhone

1. Keep the folder names intact.
2. Move the package with AirDrop, iCloud Drive, or the Files app.
3. In Files, put the five recommended `.m4a` cues in `On My iPhone/Shortcuts/PatrickFace/Sounds/` or `iCloud Drive/Shortcuts/PatrickFace/Sounds/`.
4. Save the wallpaper and Watch PNGs you plan to use into Photos. Preserve the originals in Files so Photos edits do not become the only copy.

The WAV files are edit masters. The M4A files are smaller and are the recommended inputs for iPhone Shortcuts.

## 2. Lock and Home Screen wallpapers

Choose the folder whose filename matches the iPhone display:

- iPhone 16: `1179×2556`
- iPhone 16 Plus: `1290×2796`
- iPhone 16 Pro: `1206×2622`
- iPhone 16 Pro Max: `1320×2868`

For either the `2d` or `3d` style:

1. Go to **Settings > Wallpaper > Add New Wallpaper > Photos**.
2. Select the matching file from `wallpapers/iphone/<style>/lock/`.
3. Keep the complete image edge-to-edge. If iOS enlarges it, pinch closed; turn off **Extend Wallpaper** if that option invents extra pixels at the edge.
4. Keep the system clock in the intentionally quiet upper zone. Add Lock Screen widgets only if they do not cover the face or arms.
5. Tap **Add**, then choose **Customize Home Screen**.
6. Tap **Photo** and select the matching file from `wallpapers/iphone/<style>/home/`. Do not select Blur unless you want additional blur.

Visible result: the Lock Screen has a clean clock zone and a brighter character; the paired Home Screen is darker and offsets the character so app labels remain readable. The image contains no fake clock—the time remains the live iOS clock.

## 3. Landscape StandBy photo assets

The files in `wallpapers/standby/` are native landscape display sizes. Apple describes StandBy as a clock, photo frame, widget display, and Live Activity display; iOS does **not** expose a generic “StandBy wallpaper file” importer.

Official Photos route:

1. Save the desired landscape PNGs to Photos.
2. In Photos, go to **Collections > Albums > + > New Album**, name it `Patrick Face StandBy`, and add only the selected landscape images.
3. Go to **Settings > StandBy** and turn StandBy on.
4. Connect iPhone to power, place it on its side, and wake the display.
5. Swipe left or right to the Photos view. Swipe up or down through the photo displays/collections and select the Patrick album if the current iOS build offers it.
6. If the album is not offered in the Photos view, use a photo-widget app in StandBy’s widget view and assign the same image there. The package does not claim that a PNG can replace StandBy’s system clock background.

Visible result: the character occupies one side, leaving the opposite side calm for StandBy’s live information. MagSafe can remember the preferred StandBy view per charging location.

## 4. Apple Watch Photos-face fallbacks

Select the exact display folder/file:

- Series 10/11 42 mm class: `374×446`
- Series 10/11 46 mm class: `416×496`
- Ultra 2/Ultra class: `410×502`

Each style has `time-top` and `time-bottom` variants.

1. Save the desired Watch PNGs to iPhone Photos.
2. Open the **Watch** app on iPhone.
3. Tap **Face Gallery > Photos** and choose a Photos style.
4. Choose **Choose Photos**, select the matching file (or up to 24 files), and continue.
5. Choose the system time position that matches the filename.
6. Tap **Add**.

Visible result: Apple’s live time remains functional over a static character image. The arms in these fallback photos are artwork; they do not rotate. Files under `widgets/watch/` are developer-ready imagery, not installable complications. A real complication requires a signed watchOS WidgetKit extension.

## 5. Shortcuts Home Screen icon pack

Repeat this for each app:

1. Open **Shortcuts**, tap **+**, then **Add Action**.
2. Search for **Open App**, add it, and choose the target app.
3. Tap the shortcut name/menu at the top and choose **Add to Home Screen**.
4. Tap the preview icon, choose **Choose File** or **Choose Photo**, and select the matching `shortcuts-icons/1024/<app>-1024.png`.
5. Enter the desired Home Screen label and tap **Add**.

The original signed app remains installed and remains in App Library. These icons launch an `Open App` shortcut; they do not change the app’s real icon, notification badge behavior, App Store identity, or system search result. iOS has no supported batch importer for this icon layout, so each icon and its Home Screen position are manual.

## 6. Build the five sound helper shortcuts

Create these exact shortcut names so the guide and QR fallback agree:

- `Patrick • Charge`
- `Patrick • Disconnect`
- `Patrick • Hour Chime`
- `Patrick • Low Battery`
- `Patrick • Sleep Focus`

For each helper:

1. In Shortcuts, tap **+**.
2. Add the **File** action and select the matching file in `Shortcuts/PatrickFace/Sounds/`.
3. Add **Play Sound** and make sure its input is the File output.
4. Optionally add **Show Notification** with a short label.
5. Name the shortcut exactly as listed above and run it once while iPhone is unlocked.

Use the M4A mapping:

- `charge-aac-192k.m4a` → `Patrick • Charge`
- `disconnect-aac-192k.m4a` → `Patrick • Disconnect`
- `hour-chime-aac-192k.m4a` → `Patrick • Hour Chime`
- `low-battery-aac-192k.m4a` → `Patrick • Low Battery`
- `sleep-focus-aac-192k.m4a` → `Patrick • Sleep Focus`

All five cues are original additive synthesis. They contain no speech, cloned voice, character impression, or sampled dialogue.

### Charger connected

1. Go to **Shortcuts > Automation > + > Charger**.
2. Select **Is Connected** and **Run Immediately**.
3. Choose the existing `Patrick • Charge` shortcut. If iOS shows a blank editor instead, add **Run Shortcut** and select it.
4. Save and test with the screen unlocked, then locked.

### Charger disconnected

Repeat the preceding steps with **Is Disconnected** and `Patrick • Disconnect`.

### Hour chime

1. Choose **Time of Day**.
2. Pick one desired hour, select **Daily**, and select **Run Immediately**.
3. Run `Patrick • Hour Chime`.
4. Duplicate/recreate the automation for each additional hour you want.

There is no single Apple personal-automation trigger meaning “every hour.” Do not create overnight hours unless the sound is genuinely wanted.

### Low battery

1. Choose **Battery Level**.
2. Set **Falls Below 20%** (or your preferred threshold).
3. Select **Run Immediately** and run `Patrick • Low Battery`.

### Sleep or Focus

1. Choose **Sleep** or a named **Focus**.
2. Choose **When Turning On** or **Bedtime Begins**.
3. Select **Run Immediately** and run `Patrick • Sleep Focus`.

Playback follows current volume, audio route, Focus rules, and iOS execution policy. Bluetooth may receive the sound. The automation cannot replace Apple’s built-in charge/disconnect sound; it may play in addition to it, and exact timing is not guaranteed.

## 7. Create the `Patrick Mode` software action

First create a custom Focus in **Settings > Focus > + > Custom** named `Patrick`.

Then create a normal shortcut named exactly `Patrick Mode`:

1. Add **Set Focus** → turn `Patrick` on until turned off.
2. Optional: add **Switch Between Wallpapers** and select the wallpaper pair created in section 2. If the action is unavailable on the installed iOS build, omit it.
3. Add **Set Brightness** → `35%` (adjust to taste).
4. Add **File**, select `sleep-focus-aac-192k.m4a`, then add **Play Sound**.
5. Add **Show Notification** with `Patrick Mode • Focus on`.
6. Run the shortcut once and approve only the permissions you expect.

Exact visible/software effect when it runs:

- the Patrick Focus becomes active and its Focus indicator appears;
- the prepared wallpaper pair switches only if the optional supported action was added;
- display brightness changes to 35%;
- the original non-vocal focus cue plays through the current audio route;
- a `Patrick Mode • Focus on` notification appears.

No physical case light is part of this effect.

## 8. NFC tag: supported use and phone-case constraints

### Recommended hardware

- 13.56 MHz ISO/IEC 14443 Type A, NDEF-capable `NTAG213`, `NTAG215`, or `NTAG216`.
- A **ferrite-backed / anti-metal** tag, preferably 25–30 mm rather than a tiny inlay.
- A non-metallic mount surface and a thin plastic case. Thick cases reduce range.

Ferrite backing helps a tag work near metal; it does not create power for LEDs, cancel a MagSafe magnetic field, or guarantee operation over a charging coil.

### Reliable placement

For the same iPhone to scan the tag, mount the tag on an **external object** such as a desk card, stand, bedside dock, or wall marker. Keep it away from the charger’s MagSafe ring, Qi coil, metal plate, and strong magnets.

To scan, illuminate the iPhone screen and hold the **top edge of iPhone** within roughly 0–2 cm of the tag for about a second. Do not aim the center of the phone. The phone only needs to be held near the tag; hard contact is unnecessary.

### Why a tag inside the same phone’s fitted case is not a reliable trigger

A passive tag permanently trapped against the same iPhone is already beside the reader, sits near the phone’s battery/charging/magnet hardware, and has no clean “approach then leave” event. iOS does not expose it as a continuous case-attached sensor. It may fail to discover, remain detuned, or fail to retrigger until the tag and phone are separated.

Therefore:

- do **not** promise that inserting the phone into its own tagged case will trigger every time;
- do **not** put a tag over the central MagSafe/Qi ring or under a metal plate;
- if the tag must be inside a case, treat it as a tag for **another scanning phone**, or use a removable/spare case and test it as an unsupported experiment;
- orient the ferrite/anti-metal side toward the phone/metal and the tag antenna side toward the scanning device, near an upper side area rather than the center coil.

### Create the NFC personal automation

1. Open **Shortcuts > Automation > + > NFC**.
2. Tap **Scan**, hold the top of iPhone near the external tag, and name it `Patrick External Tag`.
3. Select **Run Immediately**.
4. Choose the existing `Patrick Mode` shortcut, or add **Run Shortcut** and select it.
5. Save and test several times with the phone locked and unlocked.

For a Shortcuts NFC trigger, Apple states that the tag’s content is ignored; Shortcuts remembers its unique identifier. The tag does not need a programmed URL for this local automation.

## 9. QR and NFC URL fallback

`qr/` contains:

- `verified-create-new-shortcut-900x900.png` → `shortcuts://create-shortcut`
- `verified-run-patrick-mode-900x900.png` → `shortcuts://run-shortcut?name=Patrick%20Mode`
- `verified-official-shortcuts-guide-900x900.png` → Apple’s Shortcuts guide

Use only files prefixed `verified-`. Three first-pass QR files without that prefix are retained solely because this delivery was built under a no-delete requirement; the manifest marks them `qr-build-artifact` and they are not installation assets.

The run QR works only after a shortcut named exactly `Patrick Mode` exists. It launches software; it does not install a shortcut or a personal automation.

If desired, write the URL in `qr/NFC-NDEF-FALLBACK.txt` to the tag as an NDEF URL record. A normal iPhone background read can then show a notification that launches `Patrick Mode`; this remains separate from the device-specific personal automation. Use an NFC writer app you trust and verify the payload before locking a tag.

## 10. Widgets and complication imagery

`widgets/iphone/` contains @3x masters for Apple’s 428/430-point iPhone class:

- small: `510×510`
- medium: `1092×510`
- large: `1092×1146`

Use them in a trusted photo-widget app or as artwork in a WidgetKit project. The host app may crop or rescale on smaller device classes.

`widgets/iphone-lock-screen/` and `widgets/watch/` are implementation handoff images at the indicated @3x/@2x dimensions. PNG files alone cannot register a widget or complication. A signed iOS/watchOS app and WidgetKit extension are required.

## 11. What iOS cannot automatically import or share

- A personal automation is device-specific. Apple says it can be backed up but does not sync to another device.
- A normal shortcut can be shared later from an iPhone through an iCloud link or as a shortcut file. This Windows-built media package cannot create an Apple-validated iCloud shortcut link.
- An NFC automation’s tag association must be scanned and created on each iPhone.
- A wallpaper pair, Focus configuration, Home Screen icon placement, StandBy choice, and Photos-face selection remain manual.
- Static PNGs cannot become live Watch hands, a native third-party watch face, or a complication without an app.
- Custom cues cannot replace protected iOS system sounds. Shortcuts can only play an additional sound when its automation is allowed to run.
- A passive NFC tag cannot directly power case LEDs. Any illuminated case concept needs its own battery or wired power, LED controller, and safe charging/electrical design; NFC may only trigger separate software unless purpose-built powered hardware is added.

## Official references

- Shortcuts personal automations: <https://support.apple.com/guide/shortcuts/create-a-new-personal-automation-apdfbdbd7123/ios>
- Shortcuts setting triggers (NFC, Charger, Battery, Focus): <https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios>
- Shortcuts URL scheme: <https://support.apple.com/guide/shortcuts/open-create-and-run-a-shortcut-apda283236d7/ios>
- Run a shortcut from a URL: <https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios>
- Share shortcuts: <https://support.apple.com/guide/shortcuts/share-shortcuts-apdf01f8c054/ios>
- StandBy: <https://support.apple.com/guide/iphone/use-standby-iph878d77632/ios>
- Photos watch face: <https://support.apple.com/guide/watch/customize-the-photos-watch-face-apd501eb33b3/watchos>
- Apple widget dimensions/guidance: <https://developer.apple.com/design/human-interface-guidelines/widgets>
- Apple complication guidance: <https://developer.apple.com/design/human-interface-guidelines/complications>
- Apple NFC guidance: <https://developer.apple.com/design/human-interface-guidelines/nfc>
