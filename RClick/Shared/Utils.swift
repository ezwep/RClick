import Foundation

public class Utils {
    public static func isProtectedFolder(_ path: String) -> Bool {
        print("isProtectedFolder: \(path)")
        
        return Constants.protectedDirs.contains { protectedPath in
            print("Comparing with protected path: \(protectedPath)")
            return path == protectedPath
        }
    }
    // MARK: 
    public static func getRealHomeDir() -> String {
        let fullPath = NSHomeDirectory()
        let components = fullPath.components(separatedBy: "/")
        let limitedComponents = Array(components.prefix(3))  // Take the first 3 because the first one is an empty string (the path starts with /)
        return limitedComponents.joined(separator: "/")
    }
}
