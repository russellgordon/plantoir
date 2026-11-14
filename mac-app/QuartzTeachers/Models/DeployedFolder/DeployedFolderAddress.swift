import Foundation

/// Which address a deployed folder is shown at (#850): the same one each
/// time, so ticked tasks and quiz answers a teacher tried, which the site
/// keeps per address, are still there next time (Russell, 2026-11-13).
///
/// **A block of its own, below the range the system hands out** (the plan
/// review's M3). 49152 to 65535 is where every outgoing connection takes its
/// local port, and on Windows Hyper-V reserves moving ranges inside it, so a
/// port remembered there is often refused. 41000 to 41399 is below that and
/// outside the preview walk (8081 to 9474, `app-rules.json` → `previewPorts`),
/// so a preview and a deployed folder can never take each other's address.
///
/// **The walk starts from the folder's own name**: an FNV-1a hash of its
/// canonical path picks the first port to try, so the same folder lands on
/// the same address even after the remembered one is lost, or from a second
/// copy of Plantoir. The remembered port is tried first, because a walk that
/// once had to move on would otherwise move the address back.
///
/// `contracts/shared-rules.json` → `deployedFolderInBrowser.address` holds the
/// block and the cases, which both apps run.
nonisolated enum DeployedFolderAddress {

    // MARK: - Stored properties

    /// The first port of the block.
    static let firstPort: Int = 41000

    /// How many ports the block holds.
    static let blockSize: Int = 400

    /// Where the remembered ports are kept, keyed by canonical folder path.
    static let preferenceKey: String = "deployedFolderPorts"

    // MARK: - Functions

    /// FNV-1a, 32 bits, over the path's UTF-8 bytes.
    static func hash(of path: String) -> UInt32 {
        var value: UInt32 = 2166136261
        for byte in path.utf8 {
            value = value ^ UInt32(byte)
            value = value &* 16777619
        }
        return value
    }

    /// Where the walk starts for a folder.
    static func startingPort(forCanonicalPath path: String) -> Int {
        let offset: Int = Int(hash(of: path) % UInt32(blockSize))
        return firstPort + offset
    }

    /// Every port to try, in order: the remembered one when it is in the
    /// block, then the whole block from the folder's own starting port,
    /// wrapping round, each once.
    static func candidates(forCanonicalPath path: String, remembered: Int?) -> [Int] {
        var result: [Int] = []
        if let remembered, isInTheBlock(remembered) {
            result.append(remembered)
        }
        let start: Int = startingPort(forCanonicalPath: path) - firstPort
        var step: Int = 0
        while step < blockSize {
            let port: Int = firstPort + ((start + step) % blockSize)
            if !result.contains(port) {
                result.append(port)
            }
            step += 1
        }
        return result
    }

    /// Whether a port is one of the block's.
    static func isInTheBlock(_ port: Int) -> Bool {
        return port >= firstPort && port < firstPort + blockSize
    }

    /// The port this folder was last shown at, if any.
    static func rememberedPort(forCanonicalPath path: String, defaults: UserDefaults) -> Int? {
        guard let ports = defaults.dictionary(forKey: preferenceKey) else {
            return nil
        }
        return ports[path] as? Int
    }

    /// Remembers the port a folder is shown at.
    static func remember(port: Int, forCanonicalPath path: String, defaults: UserDefaults) {
        var ports: [String: Any] = defaults.dictionary(forKey: preferenceKey) ?? [:]
        ports[path] = port
        defaults.set(ports, forKey: preferenceKey)
    }
}
