import os
import UIKit
import UserNotifications

/// Plays a tiny generated atlas and writes the extension's remaining memory.
/// This target is compiled, but the default app does not embed it.
final class PatrickFieldTestNotificationController: UIViewController, UNNotificationContentExtension {
    private let imageView = UIImageView()
    private let memoryLabel = UILabel()
    private var frames: [UIImage] = []
    private var playTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        memoryLabel.textColor = .white
        memoryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        memoryLabel.numberOfLines = 0
        memoryLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        view.addSubview(memoryLabel)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 72),
            imageView.heightAnchor.constraint(equalToConstant: 72),
            memoryLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12),
            memoryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            memoryLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        preferredContentSize = CGSize(width: 320, height: 120)
    }

    func didReceive(_ notification: UNNotification) {
        frames = (0..<6).map(makeFrame)
        imageView.image = frames.first
        let opening = sample(frame: 0)
        memoryLabel.text = opening
        playTask = Task { @MainActor in
            for tick in 1..<24 {
                try? await Task.sleep(nanoseconds: 125_000_000)
                if Task.isCancelled { return }
                let frame = tick % max(frames.count, 1)
                imageView.image = frames[frame]
                if tick % 4 == 0 {
                    let line = sample(frame: frame)
                    memoryLabel.text = line
                }
            }
            let done = sample(frame: frames.count - 1)
            memoryLabel.text = "播完。\(done)"
            PatrickFieldTestLog.append("小图集播完。\(done)", topic: "通知扩展")
        }
    }

    private func sample(frame: Int) -> String {
        let bytes = os_proc_available_memory()
        let line = "帧 \(frame) 剩余可分配内存 \(bytes) 字节"
        NSLog("patrick field-test notification %@", line)
        PatrickFieldTestLog.append(line, topic: "通知扩展")
        return line
    }

    /// Six tiny frames, drawn here so the extension does not need image assets.
    private func makeFrame(_ index: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.systemPink.setFill()
            let shift = CGFloat(index) * 4
            context.cgContext.fillEllipse(in: CGRect(x: 14 + shift, y: 18, width: 30, height: 26))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 22, y: 26, width: 6, height: 6))
            context.cgContext.fillEllipse(in: CGRect(x: 34, y: 26, width: 6, height: 6))
        }
    }
}
