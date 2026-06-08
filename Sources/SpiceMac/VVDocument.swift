import Foundation
import UniformTypeIdentifiers

/// The document type for virt-viewer `.vv` connection files.
enum VVDocument {
    /// Content types accepted by open panels. Resolves the `.vv` extension to a
    /// UTType (declared in Info.plist as `org.spice-space.vv`).
    static var contentTypes: [UTType] {
        if let declared = UTType("org.spice-space.vv") {
            return [declared]
        }
        if let byExtension = UTType(filenameExtension: "vv") {
            return [byExtension]
        }
        return []
    }
}
