import UIKit

// Intentionally synchronous: no SwiftUI, Model, actor or Task before this marker.
AppPaths.prepare()
StartupLog.record("S0_MAIN")
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(StartupDelegate.self))
