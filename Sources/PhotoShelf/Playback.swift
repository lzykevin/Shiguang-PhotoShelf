import Foundation

extension LibraryModel {
    func rebuildPlaybackQueue() {
        guard viewerID != nil else { return }
        var ids = slideshowSelectedOnly ? viewerSelectedIDs : viewerAllIDs
        if slideshowRandom {
            ids.shuffle()
            // Keep the current photo at the start so every remaining photo gets a turn.
            if let current = viewerID, let index = ids.firstIndex(of: current) {
                ids.remove(at: index); ids.insert(current, at: 0)
            }
        }
        viewerQueue = ids
        if let current = viewerID, !ids.contains(current), let first = ids.first {
            selection = [first]; viewerID = first
        }
    }

    func preparePlayback() {
        guard viewerQueue.count > 1 else { return }
        if viewerID == viewerQueue.last {
            if slideshowRandom { rebuildPlaybackQueue() }
            else { selection = [viewerQueue[0]]; viewerID = viewerQueue[0] }
        }
    }

    /// Returns false after the final photo has had its full display interval.
    func advancePlayback() -> Bool {
        guard let current = viewerID, !viewerQueue.isEmpty else { return false }
        if current == viewerQueue.last {
            guard slideshowLoop else { return false }
            if slideshowRandom && viewerQueue.count > 1 {
                var next = viewerQueue.shuffled()
                if next.first == current { next.swapAt(0, 1) }
                viewerQueue = next
            }
            selection = [viewerQueue[0]]; viewerID = viewerQueue[0]
        } else { step(1) }
        return true
    }
}
