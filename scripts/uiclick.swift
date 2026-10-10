// SPDX-License-Identifier: BUSL-1.1
// Copyright 2026 Zyvor AI Labs Private Limited
// uiclick X Y: posts a real left click at screen point (X, Y). Accessibility "select" does not drive
// SwiftUI List selection, so scripts/test-native-ui.sh clicks the way a person does.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]) else {
    FileHandle.standardError.write("usage: uiclick X Y\n".data(using: .utf8)!)
    exit(2)
}
let point = CGPoint(x: x, y: y)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(80_000)
}
