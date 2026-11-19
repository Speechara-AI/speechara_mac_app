import CryptoKit
import Foundation
import Security

final class SpeakingNotesDraftStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let keychainService = "ai.speechara.mac.speaking-notes"
    private let keychainAccount = "local-draft-key-v1"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func load(userID: String) -> SpeakingNotesLocalDraft? {
        do {
            let encrypted = try Data(contentsOf: fileURL(for: userID))
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let data = try AES.GCM.open(box, using: encryptionKey())
            let draft = try decoder.decode(SpeakingNotesLocalDraft.self, from: data)
            return draft.authUserId == userID ? draft : nil
        } catch {
            return nil
        }
    }

    func save(_ draft: SpeakingNotesLocalDraft) throws {
        let url = fileURL(for: draft.authUserId)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try encoder.encode(draft)
        let sealed = try AES.GCM.seal(data, using: encryptionKey())
        guard let combined = sealed.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        try combined.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func remove(userID: String) {
        try? fileManager.removeItem(at: fileURL(for: userID))
    }

    private func fileURL(for userID: String) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let safeUserID = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return base
            .appendingPathComponent("Speechara", isDirectory: true)
            .appendingPathComponent("SpeakingNotes", isDirectory: true)
            .appendingPathComponent("\(safeUserID).draft", isDirectory: false)
    }

    private func encryptionKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
        return key
    }
}
