import Foundation

/// The content type a deployed folder's file is answered with (#850), by its
/// extension in any case: camera files are named `IMG_0042.JPG` (the plan
/// review's M4). The table is `contracts/shared-rules.json` →
/// `deployedFolderInBrowser.contentTypes`, and `DeployedFolderResolutionTests`
/// holds this one against it both ways.
///
/// `.wasm` must be `application/wasm`: Pyodide waits 45 seconds and gives up
/// on anything else (documentation/06, I5). `.mjs` must be JavaScript, or the
/// browser refuses the module worker under `nosniff`.
nonisolated enum DeployedFolderContentTypes {

    // MARK: - Stored properties

    /// Extension, lower case and without its dot, to type.
    static let table: [String: String] = [
        "html": "text/html; charset=utf-8",
        "htm": "text/html; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "mjs": "text/javascript; charset=utf-8",
        "json": "application/json",
        "map": "application/json",
        "wasm": "application/wasm",
        "zip": "application/zip",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "avif": "image/avif",
        "heic": "image/heic",
        "ico": "image/x-icon",
        "bmp": "image/bmp",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "woff2": "font/woff2",
        "woff": "font/woff",
        "ttf": "font/ttf",
        "otf": "font/otf",
        "pdf": "application/pdf",
        "xml": "application/xml",
        "txt": "text/plain; charset=utf-8",
        "md": "text/plain; charset=utf-8",
        "csv": "text/csv; charset=utf-8",
        "mp4": "video/mp4",
        "m4v": "video/mp4",
        "webm": "video/webm",
        "mov": "video/quicktime",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "wav": "audio/wav",
        "ogg": "audio/ogg",
        "ggb": "application/octet-stream",
    ]

    /// What a file whose extension is not in the table is answered with.
    static let unknown: String = "application/octet-stream"

    // MARK: - Functions

    /// The type for a file name.
    static func type(forFileNamed name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else {
            return unknown
        }
        let fileExtension: String = String(name[name.index(after: dot)...]).lowercased()
        if let known = table[fileExtension] {
            return known
        }
        return unknown
    }
}
