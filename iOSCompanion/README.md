# Patrick iPhone Companion

Production-oriented iOS 17 SwiftUI companion project for the existing Patrick
watch app. The apps remain separate projects, but the iPhone project now holds
an explicit reference, dependency, and Embed Watch Content phase for the watch
product. No existing file was deleted.

This is not a system-wide theme replacement and it does not install a custom
Apple Watch system face. “Watch face” in this project always means the
full-screen Patrick experience inside the Patrick app.

## Project targets

- `PatrickCompanion`: iPhone SwiftUI app, theme control center, local sound cue,
  App Intents, WatchConnectivity transport, deep links, and Live Activity
  lifecycle.
- `PatrickWidgets`: WidgetKit Home Screen and Lock Screen widgets, StandBy-ready
  small widget, plus the ActivityKit Lock Screen/StandBy and Dynamic Island
  presentations.
- `PatrickCompanionTests`: contract, deep-link, persistence, and message
  deduplication tests.

The deployment target is iOS 17.0. Xcode 16 or newer is recommended.
`PatrickFaceSuite.xcworkspace` opens the paired projects;
`PatrickCompanion.xcodeproj` also resolves the referenced watch project when
opened by itself.

## Included behavior

The control center selects **1999 CEL** or **Faithful 3D** and previews normal,
sleeping, low-battery, and charging states on a true black background. Sleep mode
supports automatic, explicit on, and explicit off behavior.

Watch synchronization uses a versioned Codable envelope with UUID
deduplication. Reachable commands use `sendMessageData`; unavailable peers use
queued user-info delivery; the newest state also uses application context. The
watch app remains authoritative for watch-only signals such as battery, Focus,
and frontmost state.

The provider exposes ten App Shortcuts: care, scene, mood, activity timer,
timer control, wake-up report, lifestyle, sleep mode, sound, and in-app face.
Timer control now also offers **休息一下** and **返回原活動**. It preserves the
original timer; returning to an originally paused timer keeps it paused.
The five additional routine-record actions below are discoverable actions for
composed Shortcuts, not five extra provider slots. Their Apple build and device
discovery still need verification.

## 2026-10-13: 晚安流程紀錄與充電回報

本輪新增原生程式，尚未 Apple 編譯或裝機。瀏覽器的[流程試演](../ecosystem/ideas.html#routine-rehearsal)只操作示範資料；App「流程」分頁只顯示本機真正收到的步驟回報，兩者不互相匯入。

晚安組合捷徑的接線次序如下；這仍是設定說明，不是已安裝的 `.shortcut`：

1. 「開始晚安流程紀錄」取得流程編號，保存為本次變數。
2. 執行系統睡眠專注動作，其後「回報晚安步驟結果」選睡眠專注、已完成、次數1。同一動作若中斷捷徑而未回報，紀錄保持「尚無回報」，不假定成功或失敗。
3. 有預先選好的鬧鐘才啟用那一筆，之後回報指定鬧鐘結果；未選鬧鐘則回報「未選用」。不建立重複鬧鐘。
4. 「執行晚安中的派大星步驟」傳入相同編號、次數1。由 App 套用睡前狀態後記錄本機結果，不能用外部結果把這步直接標成功。
5. 有選 Home 場景才執行並回報晚安燈光結果，否則回報「未選用」。
6. 「讀取晚安流程結果」取得四步摘要，可交給捷徑的顯示結果動作；App「流程」也保留最近50次紀錄。手機回報完整仍不表示 Watch Focus 或角色狀態已確認。

只有明確收到「未完成」的步驟才可用「準備重試晚安失敗步驟」，它回傳新的執行次數。另行執行那一步並傳入新次數回報；這個準備動作本身不重跑設定。舊次數、重複回報與衝突結果不覆蓋成功項；尚無回報的步驟先確認狀態，不自動重試。最多5次。不提供把所有步驟一鍵標成功的入口。

充電資料使用獨立最新狀態通道。Watch 畫面在前景觀測實際電量與充電狀態；手機「連線」頁顯示觀測時間和收到時間，超過5分鐘標記過期。離線只保留最新資料，充電試演不會生成真實觀測；這不是系統充電畫面替換，也不是背景持續監測。重設本機資料會清除流程紀錄和最後觀測。

測試入口：`ecosystem/test-routine-run.mjs` 和共用情境 `ecosystem/routine-run-fixtures.json`；Foundation 測試為 `tools/NativeRoutineRunChecks.swift`、`tools/NativeWatchStatusChecks.swift`，休息入口行為測試在 `PatrickContractTests.swift`。Windows 的 JS／結構檢查不能當作 Swift 或實機測試通過。

API依據：[Apple App Intent parameters](https://developer.apple.com/documentation/appintents/adding-parameters-to-an-app-intent)、[Return a value](https://developer.apple.com/documentation/appintents/returnsvalue)、[Watch battery level](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/batterylevel)、[Latest application context](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:))。

An NFC tag can trigger any of these by using a user-created **Shortcuts Personal
Automation → NFC → Run App Shortcut**. The app intentionally does not request
Core NFC permission: it does not passively scan, intercept, or silently act on
arbitrary tags.

`patrickface://` deep links use the same route names as watch commands:

- `patrickface://control-center`
- `patrickface://set-theme?value=cel-1999`
- `patrickface://set-theme?value=faithful-3d`
- `patrickface://set-sleep-mode?value=automatic`
- `patrickface://play-theme-sound`
- `patrickface://open-watch-face`
- `patrickface://timer`

The Patrick timer starts a local Live Activity. Its widget extension supplies a
Lock Screen presentation, all Dynamic Island regions, and a layout that scales
for StandBy.

## Mock and demo mode

Run the shared `PatrickCompanion-Demo` scheme to set `PATRICK_DEMO=1`, or enable
**Demo watch** on the Status tab. Commands then follow the real envelope path and
receive a delayed local acknowledgement without requiring an iPhone/Watch pair.
SwiftUI previews also use the same production views and approved assets.

Demo mode proves UI and local command flow only. It does not prove
WatchConnectivity scheduling, entitlements, ActivityKit authorization, widget
refresh policy, Dynamic Island hardware behavior, or signing.

## Privacy and persistence

The App Group `group.com.chans.patrickface.shared` stores only theme, visual
state, sleep preference, demo preference, timer state, pending foreground
actions, revisions, and recent message IDs. There is no account, cloud sync,
analytics SDK, advertising SDK, location, contacts, microphone recording, or
health-data access. The generated theme cue is synthesized locally and records
nothing.

The local routine ledger additionally stores step results and user-supplied
notes (up to 240 characters per receipt; latest 50 runs). Watch charging
observations are stored separately in local defaults with observation and
receipt timestamps; they are not health records or an analytics feed.

Both the app and widget use the same App Group entitlement. The standard
defaults fallback exists only so previews and unsigned development runs remain
inspectable; signed production builds must provision the App Group.
`Resources/PrivacyInfo.xcprivacy` declares the App Group (`1C8F.1`) and
development fallback (`CA92.1`) UserDefaults required reasons, no tracking, and
no collected data for both bundles.

## Artwork

`tools/sync_approved_assets.py --write` copied six PNGs byte-for-byte from the
approved watch asset catalog:

- the 1999 body, hour arm, and minute arm
- the faithful 3D body and arm
- the approved Patrick app icon, reused as the iOS marketing icon

Hashes and source paths are in `Resources/asset-provenance.json`. Charging glow,
sleep “Z”, battery/bolt badges, and all black presentation surfaces are clearly
derived at runtime in SwiftUI; no replacement character art is embedded. The
hour and minute arm images share one exact central hub and differ only in
length/angle; no theme-specific shoulder pivots or bent-arm poses are used.

## Official platform limits

- Public Apple APIs do not let this app replace the iOS appearance, install or
  select a third-party system watch face, bypass watchOS frontmost/Always-On
  policy, or guarantee launching an arbitrary watch app from iPhone.
- “Open Patrick Watch Face” opens the custom iPhone face and sends a best-effort
  route request to the paired Patrick watch app. The watch may process it only
  when watchOS allows.
- WatchConnectivity is opportunistic. Immediate delivery requires reachability;
  queued context has no user-visible delivery deadline.
- The source/project bundle hierarchy and embed dependency are configured, but
  official pairing still depends on matching Developer Portal registrations,
  provisioning profiles, signing, and a physical paired-device test.
- Independent watch apps may use companion synchronization, but must not depend
  on the iPhone as their primary data source.
- Widget timelines, StandBy placement, Live Activity visibility, and Dynamic
  Island presentation are controlled by the user and the system.
- Dynamic Island requires supported hardware. StandBy also depends on system
  configuration, charging, and orientation.
- App Intents are available to Shortcuts, Siri, Spotlight, and supported system
  surfaces. NFC Personal Automations remain subject to the user's Shortcuts
  settings and any confirmation the OS requires.
- iOS can restrict or silence foreground/background audio. The sound intent
  opens the app before playing its short local cue.

## Windows structural validation

From this directory:

```powershell
python tools/sync_approved_assets.py
python tools/validate_structure.py
python ../tools/validate_watch_project.py
python -m compileall -q tools
```

These checks parse plists, entitlements, schemes, workspace XML, asset JSON,
PNG headers, provenance, PBX target declarations, source memberships, and basic
Swift delimiter shape. Windows cannot run Apple's Swift SDK, `xcodebuild`,
`actool`, simulator tests, provisioning, or code signing.

## Remaining Mac-only steps

1. Open `PatrickFaceSuite.xcworkspace` in Xcode 16 or newer (or open
   `PatrickCompanion.xcodeproj` for iPhone-only work) and accept only intentional
   project-format updates.
2. Select one Apple Developer team for the iPhone app, widget, watch app,
   complication, and tests.
3. Register these bundle IDs and the shared App Group in the developer portal,
   then refresh provisioning profiles:
   - `com.chans.patrickface.companion`
   - `com.chans.patrickface.companion.widgets`
   - `com.chans.patrickface.companion.watchkitapp`
   - `com.chans.patrickface.companion.watchkitapp.complications`
   - `group.com.chans.patrickface.shared`
4. Build for an iOS 17+ simulator, run `PatrickCompanionTests`, and inspect all
   Swift concurrency and App Intent metadata diagnostics.
5. Run the app and widget previews, then add every supported widget family and
   start/end a Live Activity. Check Lock Screen, StandBy, and each Dynamic Island
   state on suitable devices.
6. Run `bash tools/verify_companion_on_mac.sh`; it builds both schemes, verifies
   the embedded watch/complication/widget products, and runs contract tests.
7. Test reachable, queued, and application-context messages in both directions
   on a physical paired iPhone/Apple Watch,
   then test all four App Shortcuts and an NFC Personal Automation.
8. Archive, validate, review privacy labels/capabilities, and sign for TestFlight
   or App Store distribution.

Compilation, Apple SDK validation, provisioning, signing, paired-device
delivery, and distribution are pending until those Mac steps are completed.
