import Foundation

let client = SMCClient()
let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    fputs("usage: MacFanHelper snapshot|auto|rpm <value>\n", stderr)
    exit(64)
}

do {
    switch command {
    case "snapshot":
        print(client.snapshot())
    case "auto":
        try client.restoreSystemAuto()
        print("ok=true mode=auto")
    case "rpm":
        guard arguments.count == 2, let rpm = Int(arguments[1]) else {
            fputs("usage: MacFanHelper rpm <value>\n", stderr)
            exit(64)
        }
        let appliedRPM = try client.setTargetRPM(rpm)
        print("ok=true rpm=\(appliedRPM)")
    default:
        fputs("usage: MacFanHelper snapshot|auto|rpm <value>\n", stderr)
        exit(64)
    }
} catch {
    fputs("error=\(error)\n", stderr)
    exit(1)
}
