import Foundation
import CoreServices
import PhotoLibraryCore

final class FolderMonitor {
    private var stream: FSEventStreamRef?
    private let changed: ([String]) -> Void
    private let roots: [String]
    init(paths: [String], changed: @escaping ([String]) -> Void) {
        self.changed = changed; self.roots = paths
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, _ in
            guard let info else { return }
            let changedPaths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as! [String]
            let monitor = Unmanaged<FolderMonitor>.fromOpaque(info).takeUnretainedValue()
            let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped)
            if (0..<count).contains(where: { flags[$0] & lost != 0 }) {
                monitor.changed(monitor.roots); return
            }
            let mutations = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemInodeMetaMod | kFSEventStreamEventFlagRootChanged)
            let relevant = (0..<count).filter { index in
                flags[index] & mutations != 0 && (
                    flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagRootChanged) != 0 ||
                    PhotoScanner.extensions.contains((changedPaths[index] as NSString).pathExtension.lowercased()))
            }.map { changedPaths[$0] }
            if !relevant.isEmpty { monitor.changed(relevant) }

        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }
    deinit { if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) } }
}
