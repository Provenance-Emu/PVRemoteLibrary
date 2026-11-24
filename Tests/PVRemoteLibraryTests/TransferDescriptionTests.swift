import PVRemoteLibrary
import Testing
@testable import PVRemoteLibraryUI

@Suite struct TransferDescriptionTests {
    @Test func downloadingShowsAClampedPercent() {
        #expect(TransferDescription(.downloading(0.426)).percent == "42%")
        #expect(TransferDescription(.downloading(0.999)).percent == "99%", "never 100% before it is done")
        #expect(TransferDescription(.downloading(1.7)).fraction == 1)
        #expect(TransferDescription(.downloading(-1)).percent == "0%")
    }

    @Test func phasesWithoutAnAmountAreIndeterminate() {
        for state in [TransferState.queued, .verifying, .importing] {
            #expect(TransferDescription(state).fraction == nil)
            #expect(TransferDescription(state).percent == nil)
        }
    }

    @Test func onlyRunningTransfersCanBeCancelled() {
        #expect(TransferDescription(.queued).canCancel)
        #expect(TransferDescription(.downloading(0.1)).canCancel)
        #expect(TransferDescription(.verifying).canCancel)
        #expect(!TransferDescription(.importing).canCancel)
        #expect(!TransferDescription(.failed("x")).canCancel)
    }

    @Test func aFailureCarriesItsReason() {
        let description = TransferDescription(.failed("Not enough free space"))
        #expect(description.failure == "Not enough free space")
        #expect(description.phase == "Couldn't download")
    }
}
