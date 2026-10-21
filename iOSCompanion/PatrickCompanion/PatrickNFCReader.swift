#if os(iOS)
import CoreNFC
import Foundation

/// Optional sticker read. No NFC entitlement and no background scan. Shortcuts
/// can run 「出門」 and 「派大星晚安」 without this session.
final class PatrickNFCReader: NSObject, NFCNDEFReaderSessionDelegate {
    static let shared = PatrickNFCReader()

    var onPhrase: ((PatrickButlerPhrase) -> Void)?
    var onUnavailable: (() -> Void)?
    private var session: NFCNDEFReaderSession?
    private var handled = false

    @discardableResult
    func scanIfAvailable() -> Bool {
        guard NFCNDEFReaderSession.readingAvailable else {
            DispatchQueue.main.async { self.onUnavailable?() }
            return false
        }
        handled = false
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = "靠近貼紙"
        self.session = session
        session.begin()
        return true
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        self.session = nil
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard claim() else { return }
        for message in messages { publish(message) }
        session.invalidate()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard claim() else { return }
        guard let tag = tags.first else {
            session.invalidate()
            return
        }
        session.connect(to: tag) { error in
            if error != nil {
                session.invalidate()
                return
            }
            tag.queryNDEFStatus { status, _, error in
                if error != nil || status == .notSupported {
                    session.invalidate()
                    return
                }
                tag.readNDEF { message, _ in
                    if let message { self.publish(message) }
                    session.alertMessage = "讀到了"
                    session.invalidate()
                }
            }
        }
    }

    private func claim() -> Bool {
        if handled { return false }
        handled = true
        return true
    }

    private func publish(_ message: NFCNDEFMessage) {
        for record in message.records {
            guard let text = String(data: record.payload, encoding: .utf8),
                  let phrase = PatrickNFCHook.phrase(in: text) else { continue }
            DispatchQueue.main.async { self.onPhrase?(phrase) }
            return
        }
    }
}
#endif
