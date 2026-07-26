import Foundation

public struct HiddenFilePolicy: Sendable {
    public var hiddenNames: Set<String>
    public var hiddenDirectoryNames: Set<String>

    public init(
        hiddenNames: Set<String> = [".DS_Store"],
        hiddenDirectoryNames: Set<String> = [
            ".git", ".hg", ".svn", "node_modules", ".build", "DerivedData",
            ".venv", "__pycache__",
        ]
    ) {
        self.hiddenNames = hiddenNames
        self.hiddenDirectoryNames = hiddenDirectoryNames
    }

    public func shouldShow(
        name: String,
        isDirectory: Bool,
        showAllFiles: Bool
    ) -> Bool {
        if showAllFiles { return true }
        if hiddenNames.contains(name) { return false }
        if isDirectory, hiddenDirectoryNames.contains(name) { return false }
        return true
    }

    public func shouldShow(url: URL, showAllFiles: Bool) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return shouldShow(
            name: url.lastPathComponent,
            isDirectory: values?.isDirectory == true,
            showAllFiles: showAllFiles
        )
    }

    public func shouldDescend(into url: URL, showAllFiles: Bool = false) -> Bool {
        let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            return false
        }
        return shouldShow(
            name: url.lastPathComponent,
            isDirectory: true,
            showAllFiles: showAllFiles
        )
    }
}
