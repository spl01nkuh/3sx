import Foundation

// Exercise Apple's bundle-layout detection with the same folder used by the
// personal IPA packager. Reading Info.plist directly does not test this.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let manager = FileManager.default
let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: temporary) }
let app = temporary.appendingPathComponent("3SX.app")
try manager.copyItem(at: source, to: app)
let dataDirectory = app.appendingPathComponent("game-data")
try manager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
try Data("bundle layout test".utf8).write(to: dataDirectory.appendingPathComponent("SF33RD.AFS"))
guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "org.crowdedstreet.3sx" else {
    fatalError("Apple Foundation could not read the app's bundle identifier")
}
guard bundle.resourceURL?.lastPathComponent == "3SX.app" else {
    fatalError("Apple Foundation detected a non-flat bundle layout")
}
print("Apple bundle metadata and preloaded data layout verified")
