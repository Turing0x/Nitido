import SwiftUI
import UniformTypeIdentifiers

struct PageReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var pageIDs: [UUID]
    @Binding var draggingPageID: UUID?
    let onCommit: ([UUID]) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggingPageID,
              draggingPageID != targetID,
              let source = pageIDs.firstIndex(of: draggingPageID),
              let destination = pageIDs.firstIndex(of: targetID)
        else { return }

        withAnimation {
            pageIDs.move(
                fromOffsets: IndexSet(integer: source),
                toOffset: destination > source ? destination + 1 : destination
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        onCommit(pageIDs)
        draggingPageID = nil
        return true
    }
}
