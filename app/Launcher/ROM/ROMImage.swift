import CryptoKit
import Foundation

/// A ROM prepared for extraction: copied out of wherever the player picked it, converted to the
/// big-endian .z64 layout every game's extractor reads, and fingerprinted.
nonisolated struct ROMImage: Sendable {
  enum PrepareError: LocalizedError {
    case notAROM(String)

    var errorDescription: String? {
      switch self {
      case .notAROM(let name):
        "\(name) isn't a ROM iHarbour can read. It takes .z64, .n64, and .v64 files."
      }
    }
  }

  /// The .z64 copy, in a temporary folder of its own. Delete it with `discard()`.
  let url: URL
  let originalName: String
  /// SHA-1 of the .z64 data, lowercase hex.
  let sha1: String
  /// The two-letter game code at 0x3C of the ROM header.
  let gameCode: String

  /// The three byte orders ROM dumps come in, by their first four bytes.
  private enum ByteOrder {
    /// .z64: as the cartridge stores it.
    case bigEndian
    /// .v64: 16-bit words byte-swapped.
    case byteSwapped
    /// .n64: 32-bit words little-endian.
    case littleEndian

    init?(magic: some Collection<UInt8>) {
      switch Array(magic.prefix(4)) {
      case [0x80, 0x37, 0x12, 0x40]: self = .bigEndian
      case [0x37, 0x80, 0x40, 0x12]: self = .byteSwapped
      case [0x40, 0x12, 0x37, 0x80]: self = .littleEndian
      default: return nil
      }
    }
  }

  /// Copies the ROM at `url` (which may come from the document picker and lie outside the
  /// sandbox) into a temporary folder as .z64.
  @concurrent
  static func prepare(from url: URL) async throws -> Self {
    let isAccessing = url.startAccessingSecurityScopedResource()
    defer {
      if isAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    var data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.count >= 0x1000, data.count.isMultiple(of: 4), let order = ByteOrder(magic: data)
    else {
      throw PrepareError.notAROM(url.lastPathComponent)
    }

    switch order {
    case .bigEndian:
      break
    case .byteSwapped:
      data.withUnsafeMutableBytes { bytes in
        for i in stride(from: 0, to: bytes.count, by: 2) {
          bytes.swapAt(i, i + 1)
        }
      }
    case .littleEndian:
      data.withUnsafeMutableBytes { bytes in
        for i in stride(from: 0, to: bytes.count, by: 4) {
          bytes.swapAt(i, i + 3)
          bytes.swapAt(i + 1, i + 2)
        }
      }
    }

    let sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let gameCode = String(bytes: data[0x3C ..< 0x3E], encoding: .ascii) ?? ""

    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ROM-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    // Extractors check the extension, and only take a lowercase one.
    let copy = directory.appending(
      path: url.deletingPathExtension().lastPathComponent + ".z64",
      directoryHint: .notDirectory,
    )
    try data.write(to: copy)
    return Self(url: copy, originalName: url.lastPathComponent, sha1: sha1, gameCode: gameCode)
  }

  func discard() {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
  }
}
