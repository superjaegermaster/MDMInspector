// Prints the CGWindowID of the MDM Inspector window.
//
// `screencapture -l <id>` captures one specific window regardless of what is in
// front, so documentation screenshots can be taken while other apps hold focus.
//
// Build:  swiftc -O tools/windowid.swift -o /tmp/windowid
// Usage:  /tmp/windowid [process name]

import CoreGraphics
import Foundation

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MDMInspector"

guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write("could not read the window list\n".data(using: .utf8)!)
    exit(1)
}

// Prefer the largest on-screen window owned by the target process.
var best: (id: Int, area: Int)?
for win in list {
    guard let owner = win[kCGWindowOwnerName as String] as? String,
          owner.lowercased().contains(target.lowercased()),
          let num = win[kCGWindowNumber as String] as? Int,
          let layer = win[kCGWindowLayer as String] as? Int,
          layer == 0 else { continue }
    let bounds = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let w = (bounds["Width"] as? Double) ?? 0
    let h = (bounds["Height"] as? Double) ?? 0
    let area = Int(w * h)
    if best == nil || area > best!.area { best = (num, area) }
}

guard let found = best else {
    FileHandle.standardError.write("no on-screen window for \(target)\n".data(using: .utf8)!)
    exit(2)
}
print(found.id)