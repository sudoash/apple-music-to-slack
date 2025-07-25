import Cocoa

@main
struct AppleMusicToSlackApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        
        // Prevent the app from terminating when all windows are closed
        app.setActivationPolicy(.accessory)
        
        app.run()
    }
}
