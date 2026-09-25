# Patrick Face

同一個倉庫裡的 Apple Watch 動態錶盤合集：

1. **派大星 Patrick Face**（主線）— 1999 第一季風格，手臂當真實時針／分針，含 iPhone companion 與主題包。
2. **軌道錶盤 Orbit Face**（併入）— 金色軌道＋彗星秒針的抽象動態錶盤原型。

## 派大星 · 当前效果

- 纯黑 OLED 背景，没有圆形表盘。
- 边缘 12 个低调刻度，顶部另有数字时间。
- 两只手臂是共用同一胸部中心轴的真实时针、分针，秒数也参与连续角度计算；动作只增加有界角度偏移，不移动轴心。
- 每 12 秒播放一次有界揮手动作；1.8 秒后精确回到当前时间。
- 点击角色触发跳动与 watchOS 触觉接口。
- 睡眠、低电量、充电状态有独立动画表现。
- 双击手表切换第一季 2D／第一季 Toon 3D；长按立即揮手。
- Always-On、非前台和低电量模式会停止环境动画、降低角色亮度并限制更新频率。
- WidgetKit complication 支援 `accessoryCircular`、`accessoryRectangular` 与
  `accessoryInline`；显示数字时间、主题／状态，并点按打开全屏 App。

## 軌道錶盤 · Orbit Face

獨立的抽象錶盤原型（從桌面 `OrbitWatchFace` 併入）：

- 象牙時針／分針共用中心軸。
- 金色／珊瑚色軌道弧與彗星秒針尾跡。
- Always-On 降低更新與發光。
- 瀏覽器預覽：`preview-orbit/index.html`
- watchOS 工程：`OrbitFace.xcodeproj`

## 浏览器预览

仓库根目录入口：

`http://127.0.0.1:8765/`（需在仓库根目录启动 `python -m http.server 8765`）

或直接打开：

- 派大星：`preview/index.html`
- 軌道：`preview-orbit/index.html`

派大星页面控制：

- `第一季 2D`／`第一季 Toon 3D`：切换主题。
- `揮手`：播放手臂动作。
- `回位测试`：验证动作结束后手臂误差为 0。
- `睡眠`／`低电量`／`充电`：模拟状态。

测试：

```powershell
cd preview
node test-motion.mjs
```

## watchOS 工程

在 macOS 上用 Xcode 16 或更新版本打开：

`PatrickFace.xcodeproj`

工程有两个 target：

- `PatrickFace`：全屏 watchOS 10+ App。
- `PatrickFaceComplications`：嵌入 App 的 WidgetKit extension。

App、complication、iPhone companion 与 widget 统一透过 App Group
`group.com.chans.patrickface.shared` 共享可持久化状态。
Complication 使用 `patrickface://face?source=complication` 打开 App，不把可能延迟的
timeline 主题写回 App；其他来源可选择附加 `theme=cel|clay`。App 会验证 scheme、
route 与主题后才处理。双击切换主题或状态改变时才要求
`WidgetCenter` 重新载入。

Complication 预先产生当前一小时的逐分钟 entries，并在 timeline 结束后才要求新
timeline；这样数字时间可逐分钟前进，不需要每分钟消耗一次 reload 请求。

这不是第三方系统表盘。正式渠道的实现是全屏 watchOS App 加 WidgetKit
complication，并配合 Apple Watch 的“返回时钟／显示上一应用”设置获得接近表盘的
体验；系统仍控制前台时长、Always-On 与 complication 更新预算。

旧的 `dial`、`body`、`body-night`、`arm` 素材按要求保留在磁碟上，但 production
Swift source 不再引用它们；运行时画面只使用批准的 `season1-*` 分层素材。

## Windows 可执行验证

```powershell
node preview/test-motion.mjs
python tools/validate_watch_project.py
python iOSCompanion/tools/validate_structure.py
```

验证脚本会检查 plist／entitlements、App Group、URL scheme、extension target 与
embed phase、三种 complication family、timeline policy、共享角度计算、批准素材
透明度，以及旧圆形表盘素材没有被 Swift runtime 引用。

Windows 没有 Apple watchOS SDK、`xcodebuild`、watchOS Simulator、签名与
provisioning 工具，因此这里不能完成 Swift 编译、asset catalog 编译、Widget
Gallery/深连结实机测试、Always-On 功耗测试、Archive 或签名。

## Mac 最终步骤

1. 用 Xcode 16+ 打开 `iOSCompanion/PatrickFaceSuite.xcworkspace`，为 iPhone、
   widget、watch 与 complication target 选择同一个 Team。
2. 注册 `com.chans.patrickface.companion`、其 `.widgets`、
   `.watchkitapp` 与 `.watchkitapp.complications` 子 bundle ID，并确认
   `group.com.chans.patrickface.shared` 已加入四个 provisioning profiles。
3. 在 watchOS 10+ Simulator Build；在 Widget Gallery 检查 Circular、
   Rectangular、Inline，点按每种 complication 验证冷／热启动 deep link。
4. 在真机检查 2D/3D 切换后的 complication reload、Always-On、低电量、睡眠专注、
   充电、触觉与 1.8 秒手臂精确回位。
5. 在 `iOSCompanion/` 执行
   `bash tools/verify_companion_on_mac.sh`，再以实机验证 reachable、queued、
   application-context 与独立 watch 使用情境。
6. 执行 Archive、Validate App，再准备 App Store Connect 素材与送审。

## 主要文件

- `preview/`：派大星可交互预览。
- `preview-orbit/`：軌道錶盤浏览器预览。
- `PatrickFace/PatrickFaceView.swift`：派大星 watchOS 主实现。
- `OrbitFace/DynamicFaceView.swift`：軌道錶盤 watchOS 主实现。
- `OrbitFace.xcodeproj`：軌道錶盤独立 Xcode 工程。
- `PatrickFace/PatrickShared.swift`：共享主题、状态、时针角度与 deep-link contract。
- `PatrickFaceComplications/PatrickFaceComplications.swift`：三种 WidgetKit complication。
- `tools/validate_watch_project.py`：Windows source/project consistency gate。
- `comparison-season1-3d/assets/`：第一季 2D 分层原画。
- `preview/assets/season1-3d-*.png`：忠实 3D 分层原画。
- `style-library/`：六种风格、240 个模块化素材文件。
- `motion-lab/`：动画优先级、性能分级与实验实现。
- `tools/process_final_assets.py`：蓝幕去除和透明层处理。
- `tools/sync_xcode_assets.py`：将批准素材同步到 Xcode 资产目录。
