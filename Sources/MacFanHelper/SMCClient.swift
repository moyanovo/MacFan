import Foundation
import IOKit

struct SMCClient {
    func snapshot() -> String {
        guard appleSMCServiceExists() else {
            return unavailableSnapshot(reason: "apple_smc_missing")
        }

        return unavailableSnapshot(reason: "smc_adapter_read_disabled")
    }

    func restoreSystemAuto() throws {
        _ = appleSMCServiceExists()
    }

    func setTargetRPM(_ rpm: Int) throws {
        guard rpm > 0 else { throw SMCClientError.invalidRPM }
        _ = appleSMCServiceExists()
    }

    private func appleSMCServiceExists() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }

    private func unavailableSnapshot(reason: String) -> String {
        "temperature=nil currentRPM=nil minRPM=nil maxRPM=nil control=false reason=\(reason)"
    }
}

enum SMCClientError: Error {
    case invalidRPM
}
