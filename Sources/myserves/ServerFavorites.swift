import Foundation
import Darwin

// Manages the macOS "Connect to Server" (⌘K) favourites — the shared file list
// `com.apple.LSSharedFileList.FavoriteServers` — via the private LSSharedFileList
// API loaded at runtime through dlopen/dlsym.
//
// Why this works without Full Disk Access
// ---------------------------------------
// The favourites are stored in
//   ~/Library/Application Support/com.apple.sharedfilelist/
//     com.apple.LSSharedFileList.FavoriteServers.sfl3   (sfl2 pre-Ventura, sfl4 on macOS 26+)
// as an NSKeyedArchiver blob, and that directory is TCC-protected: a plain process
// gets "Operation not permitted" trying to read it directly. But the *authoritative*
// state lives inside the `sharedfilelistd` daemon. The LSSharedFileList functions are
// thin clients that talk to that daemon over XPC, so every read and write here goes
// through a process that already holds the entitlement. No Full Disk Access required,
// and Finder's ⌘K dialog reflects the changes immediately (verified live on macOS 26).
//
// LSSharedFileList was dropped from Apple's public headers around macOS 10.10–12, but
// the implementation is still present and functional in CoreServices — including a
// first-class `kLSSharedFileListFavoriteServers` symbol — reached here via dlsym.
//
// The dlopen/dlsym symbol set and the `kLSSharedFileListItemLast` → OpaquePointer
// sentinel handling are adapted from 7onnie/mysides (MIT), which manages the Finder
// *sidebar* list; the non-obvious sentinel detail (passing it as CFTypeRef? triggers
// swift_unknownObjectRetain(0x2) and segfaults) is credited to that project.
final class ServerFavorites {

    // MARK: - Private C function signatures

    private typealias SFLCreateFn   = @convention(c) (CFAllocator?, CFString, CFTypeRef?) -> CFTypeRef?
    private typealias SFLSnapshotFn = @convention(c) (CFTypeRef, UnsafeMutablePointer<UInt32>) -> CFArray?
    private typealias SFLNameFn     = @convention(c) (CFTypeRef) -> Unmanaged<CFString>?
    private typealias SFLURLFn      = @convention(c) (CFTypeRef, UInt32, UnsafeMutablePointer<CFTypeRef?>?) -> Unmanaged<CFURL>?
    // The `after` param is OpaquePointer? because kLSSharedFileListItemLast is the
    // sentinel integer 0x2, not a real CF object; using CFTypeRef? makes Swift try to
    // retain 0x2 and crash.
    private typealias SFLInsertFn   = @convention(c) (CFTypeRef, OpaquePointer?, CFString?, CFTypeRef?, CFURL, CFDictionary?, CFArray?) -> CFTypeRef?
    private typealias SFLRemoveFn   = @convention(c) (CFTypeRef, CFTypeRef) -> OSStatus

    // MARK: - Loaded symbols

    private let list: CFTypeRef          // LSSharedFileListRef for FavoriteServers
    private let kLast: OpaquePointer     // kLSSharedFileListItemLast sentinel (0x2)
    private let _snapshot: SFLSnapshotFn
    private let _getName:  SFLNameFn
    private let _getURL:   SFLURLFn
    private let _insert:   SFLInsertFn
    private let _remove:   SFLRemoveFn

    // Resolve flags from the old public header, stable across macOS versions.
    // NoUserInteraction | DoNotMount keeps `list` from ever blocking on the network.
    private static let resolveFlags: UInt32 = 1 | 2

    struct Entry {
        let name: String
        let url: String
    }

    // MARK: - Init

    init() throws {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreServices.framework/CoreServices",
            RTLD_LAZY
        ) else {
            throw MyservesError.apiUnavailable("dlopen failed: \(String(cString: dlerror()))")
        }

        func sym<T>(_ name: String) throws -> T {
            guard let ptr = dlsym(handle, name) else {
                throw MyservesError.apiUnavailable("symbol not found: \(name)")
            }
            return unsafeBitCast(ptr, to: T.self)
        }

        let create: SFLCreateFn = try sym("LSSharedFileListCreate")
        _snapshot = try sym("LSSharedFileListCopySnapshot")
        _getName  = try sym("LSSharedFileListItemCopyDisplayName")
        _getURL   = try sym("LSSharedFileListItemCopyResolvedURL")
        _insert   = try sym("LSSharedFileListInsertItemURL")
        _remove   = try sym("LSSharedFileListItemRemove")

        guard let lastPtr = dlsym(handle, "kLSSharedFileListItemLast") else {
            throw MyservesError.apiUnavailable("symbol not found: kLSSharedFileListItemLast")
        }
        let lastRaw = lastPtr.assumingMemoryBound(to: UInt.self).pointee
        guard let lastOpaque = OpaquePointer(bitPattern: lastRaw) else {
            throw MyservesError.apiUnavailable("kLSSharedFileListItemLast is zero")
        }
        kLast = lastOpaque

        guard let serversPtr = dlsym(handle, "kLSSharedFileListFavoriteServers") else {
            throw MyservesError.apiUnavailable("symbol not found: kLSSharedFileListFavoriteServers")
        }
        let kServers = serversPtr.assumingMemoryBound(to: CFString.self).pointee

        guard let listRef = create(nil, kServers, nil) else {
            throw MyservesError.apiUnavailable("LSSharedFileListCreate returned nil for FavoriteServers")
        }
        list = listRef
    }

    // MARK: - Read

    func entries() -> [Entry] {
        return snapshot().map { item in
            let name = _getName(item)?.takeRetainedValue() as String? ?? "(unresolvable)"
            let url  = _getURL(item, Self.resolveFlags, nil)?.takeRetainedValue() as URL?
            return Entry(name: name, url: url?.absoluteString ?? "")
        }
    }

    // MARK: - Write

    /// Add a favourite server. `name` is optional; when nil, Finder derives the
    /// display label from the URL. Refuses duplicates by URL unless `force`.
    func add(url: URL, name: String?, force: Bool) throws {
        if !force {
            let target = url.absoluteString
            if entries().contains(where: { $0.url == target }) {
                throw MyservesError.duplicate(target)
            }
        }
        let cfName = name as CFString?
        guard _insert(list, kLast, cfName, nil, url as CFURL, nil, nil) != nil else {
            throw MyservesError.apiUnavailable("LSSharedFileListInsertItemURL returned nil")
        }
    }

    /// Remove every favourite whose display name OR URL matches `query`.
    /// Returns the number removed.
    @discardableResult
    func remove(matching query: String) throws -> Int {
        var removed = 0
        for item in snapshot() {
            let name = _getName(item)?.takeRetainedValue() as String? ?? ""
            let url  = _getURL(item, Self.resolveFlags, nil)?.takeRetainedValue() as URL?
            if name == query || url?.absoluteString == query {
                let status = _remove(list, item)
                guard status == 0 else {
                    throw MyservesError.apiUnavailable("LSSharedFileListItemRemove failed: OSStatus \(status)")
                }
                removed += 1
            }
        }
        if removed == 0 {
            throw MyservesError.itemNotFound(query)
        }
        return removed
    }

    // MARK: - Private

    private func snapshot() -> [CFTypeRef] {
        var seed: UInt32 = 0
        return (_snapshot(list, &seed) as? [CFTypeRef]) ?? []
    }
}
