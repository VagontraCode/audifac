import AVFoundation
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "AudifacMediaLibrary") {
      AudifacMediaLibrary.register(with: registrar)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// iOS side of the `audifac/media_library` channel (see MediaLibraryChannel.kt
/// for Android): songs from the Apple Music library (downloaded, DRM-free) and
/// audio files the user copies into the app's Documents folder (Files app /
/// Finder), with tags, artwork, codec details, lyrics and chapters from AVAsset.
/// (Kept in this file so the Xcode project needs no changes.)
final class AudifacMediaLibrary: NSObject {
  static let audioExtensions: Set<String> = [
    "mp3", "m4a", "m4b", "aac", "alac", "flac", "wav", "aif", "aiff", "aifc", "caf", "mp4", "opus", "ogg",
  ]

  private let queue = DispatchQueue(label: "audifac.media", qos: .userInitiated)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "audifac/media_library", binaryMessenger: registrar.messenger())
    let instance = AudifacMediaLibrary()
    channel.setMethodCallHandler { call, result in instance.handle(call, result: result) }
    // Keep both alive for the app's lifetime.
    retained.append((channel, instance))
  }

  private static var retained: [(FlutterMethodChannel, AudifacMediaLibrary)] = []

  /// Dart id → Apple persistent id (Dart ids drop the top bit to stay positive).
  private var persistentIds: [Int64: MPMediaEntityPersistentID] = [:]

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    func background(_ work: @escaping () -> Any?) {
      queue.async {
        let value = work()
        DispatchQueue.main.async { result(value) }
      }
    }
    switch call.method {
    case "requestMusicAccess":
      MPMediaLibrary.requestAuthorization { status in
        DispatchQueue.main.async { result(status == .authorized) }
      }
    case "getSongs":
      background { self.songs() }
    case "scanStorage":
      background { self.scanDocuments() }
    case "readMetadata":
      let paths = args["paths"] as? [String] ?? []
      background { paths.map { self.metadata(path: $0) } }
    case "inspectAudio":
      let locations = args["locations"] as? [String] ?? []
      background { locations.map { self.inspect(location: $0) } }
    case "getArtwork":
      let size = args["size"] as? Int ?? 300
      let id = (args["id"] as? NSNumber)?.int64Value
      let path = args["path"] as? String
      background { self.artwork(id: id, path: path, size: size).map { FlutterStandardTypedData(bytes: $0) } }
    case "cacheArtwork":
      let id = (args["id"] as? NSNumber)?.int64Value
      let path = args["path"] as? String
      let key = args["key"] as? String ?? "art"
      background { self.cacheArtwork(id: id, path: path, key: key) }
    case "readLyrics":
      let location = args["location"] as? String ?? ""
      background { self.lyrics(location: location) }
    case "readChapters":
      let location = args["location"] as? String ?? ""
      background { self.chapters(location: location) }
    case "grantedFolders":
      result([])
    case "appVersion":
      let info = Bundle.main.infoDictionary
      result("\(info?["CFBundleShortVersionString"] as? String ?? "?")+\(info?["CFBundleVersion"] as? String ?? "?")")
    case "saveTextDocument":
      // Saved into Documents: visible in the Files app under "On My iPhone".
      let name = args["name"] as? String ?? "audifac.txt"
      let text = args["text"] as? String ?? ""
      background {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = dir.appendingPathComponent(name)
        do { try text.write(to: url, atomically: true, encoding: .utf8); return name } catch { return nil }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Library

  /// Songs Android-style (see Song.fromMap): ids from persistent ids.
  private func songs() -> [[String: Any?]] {
    guard MPMediaLibrary.authorizationStatus() == .authorized else { return [] }
    let items = MPMediaQuery.songs().items ?? []
    return items.compactMap { item -> [String: Any?]? in
      // Cloud-only or DRM items can't be played by AVPlayer.
      guard let url = item.assetURL, !item.hasProtectedAsset, !item.isCloudItem else { return nil }
      let added = item.dateAdded.timeIntervalSince1970
      persistentIds[Self.positive(item.persistentID)] = item.persistentID
      return [
        "id": Self.positive(item.persistentID),
        "uri": url.absoluteString,
        "path": nil,
        "title": item.title,
        "artist": item.artist,
        "artistId": Self.positive(item.artistPersistentID),
        "album": item.albumTitle,
        "albumId": Self.positive(item.albumPersistentID),
        "durationMs": Int(item.playbackDuration * 1000),
        "track": item.discNumber * 1000 + item.albumTrackNumber,
        "dateAdded": Int(added),
        "dateModified": Int(added),
        "isMusic": item.mediaType.contains(.music),
        "isPodcast": item.mediaType.contains(.podcast),
      ]
    }
  }

  /// Persistent ids are UInt64; Dart ids are positive Int64 (negative ids
  /// are for files found by the storage scan).
  private static func positive(_ id: MPMediaEntityPersistentID) -> Int64 {
    Int64(bitPattern: id) & Int64.max
  }

  private func scanDocuments() -> [String: Any] {
    let start = Date()
    var files: [[String: Any]] = []
    let fm = FileManager.default
    if let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
       let walker = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]) {
      for case let url as URL in walker {
        guard Self.audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { continue }
        files.append([
          "location": url.path,
          "path": url.path,
          "size": values?.fileSize ?? 0,
          "modified": Int((values?.contentModificationDate ?? Date()).timeIntervalSince1970 * 1000),
        ])
      }
    }
    return [
      "found": files.count,
      "newlyIndexed": 0,
      "unindexed": files,
      "elapsedMs": Int(Date().timeIntervalSince(start) * 1000),
    ]
  }

  private func asset(_ location: String) -> AVURLAsset {
    let url = location.hasPrefix("/") ? URL(fileURLWithPath: location) : (URL(string: location) ?? URL(fileURLWithPath: location))
    return AVURLAsset(url: url)
  }

  private func string(_ items: [AVMetadataItem], _ id: AVMetadataIdentifier) -> String? {
    AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first?.stringValue
  }

  private func metadata(path: String) -> [String: Any?] {
    let a = asset(path)
    let common = a.commonMetadata
    let duration = a.duration.seconds
    return [
      "path": path,
      "readable": a.isPlayable,
      "title": string(common, .commonIdentifierTitle),
      "artist": string(common, .commonIdentifierArtist),
      "album": string(common, .commonIdentifierAlbumName),
      "durationMs": duration.isFinite ? Int(duration * 1000) : nil,
      "mimeType": Self.mime(forExtension: (path as NSString).pathExtension),
    ]
  }

  static func mime(forExtension ext: String) -> String? {
    switch ext.lowercased() {
    case "mp3": return "audio/mpeg"
    case "m4a", "m4b", "mp4", "aac", "alac": return "audio/mp4"
    case "flac": return "audio/flac"
    case "wav": return "audio/wav"
    case "aif", "aiff", "aifc": return "audio/aiff"
    case "caf": return "audio/x-caf"
    case "opus", "ogg": return "audio/ogg"
    default: return nil
    }
  }

  /// Codec, sample rate, channels, bit depth, bitrate (see AudioInspector.kt).
  private func inspect(location: String) -> [String: Any?] {
    let a = asset(location)
    var info: [String: Any?] = ["location": location, "ok": false]
    guard let track = a.tracks(withMediaType: .audio).first else { return info }
    if let desc = track.formatDescriptions.first {
      let format = desc as! CMAudioFormatDescription
      if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
        info["sampleRate"] = Int(asbd.mSampleRate)
        info["channels"] = Int(asbd.mChannelsPerFrame)
        if asbd.mBitsPerChannel > 0 { info["bitDepth"] = Int(asbd.mBitsPerChannel) }
        info["codecMime"] = Self.codecMime(asbd.mFormatID)
      }
    }
    let rate = track.estimatedDataRate
    if rate > 0 { info["bitrate"] = Int(rate) }
    let duration = a.duration.seconds
    if duration.isFinite { info["durationMs"] = Int(duration * 1000) }
    let common = a.commonMetadata
    info["genre"] = string(a.metadata, .iTunesMetadataUserGenre) ?? string(a.metadata, .id3MetadataContentType)
    info["year"] = string(common, .commonIdentifierCreationDate).map { String($0.prefix(4)) }
    info["albumArtist"] = string(a.metadata, .iTunesMetadataAlbumArtist)
    info["composer"] = string(a.metadata, .iTunesMetadataComposer)
    info["ok"] = info["codecMime"] != nil
    return info
  }

  static func codecMime(_ id: AudioFormatID) -> String? {
    switch id {
    case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_LD: return "audio/mp4a-latm"
    case kAudioFormatAppleLossless: return "audio/alac"
    case kAudioFormatFLAC: return "audio/flac"
    case kAudioFormatMPEGLayer3: return "audio/mpeg"
    case kAudioFormatMPEGLayer2: return "audio/mpeg-l2"
    case kAudioFormatLinearPCM: return "audio/raw"
    case kAudioFormatOpus: return "audio/opus"
    case kAudioFormatAC3: return "audio/ac3"
    case kAudioFormatEnhancedAC3: return "audio/eac3"
    default: return nil
    }
  }

  // MARK: Artwork, lyrics, chapters

  private func artwork(id: Int64?, path: String?, size: Int) -> Data? {
    var image: UIImage?
    if let path = path {
      let data = AVMetadataItem.metadataItems(from: asset(path).commonMetadata, filteredByIdentifier: .commonIdentifierArtwork).first?.dataValue
      image = data.flatMap { UIImage(data: $0) }
    } else if let id = id, MPMediaLibrary.authorizationStatus() == .authorized {
      let query = MPMediaQuery.songs()
      let persistent = persistentIds[id] ?? UInt64(bitPattern: id)
      query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: persistent), forProperty: MPMediaItemPropertyPersistentID))
      image = query.items?.first?.artwork?.image(at: CGSize(width: size, height: size))
    }
    guard let source = image else { return nil }
    let side = CGFloat(size)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
    let scaled = renderer.image { _ in source.draw(in: CGRect(x: 0, y: 0, width: side, height: side)) }
    return scaled.jpegData(compressionQuality: 0.85)
  }

  private func cacheArtwork(id: Int64?, path: String?, key: String) -> String? {
    guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    let url = dir.appendingPathComponent("art_\(key).jpg")
    if FileManager.default.fileExists(atPath: url.path) { return url.path }
    guard let data = artwork(id: id, path: path, size: 512) else { return nil }
    do { try data.write(to: url); return url.path } catch { return nil }
  }

  private func lyrics(location: String) -> [String: Any]? {
    if location.hasPrefix("/") {
      let base = (location as NSString).deletingPathExtension
      for ext in ["lrc", "LRC", "txt"] {
        if let text = try? String(contentsOfFile: "\(base).\(ext)", encoding: .utf8), !text.isEmpty {
          return ["text": text, "source": "file"]
        }
      }
    }
    if let text = asset(location).lyrics, !text.isEmpty { return ["text": text, "source": "tags"] }
    return nil
  }

  private func chapters(location: String) -> [[String: Any]] {
    let a = asset(location)
    let groups = a.chapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)
    return groups.map { group in
      let title = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first?.stringValue ?? ""
      return ["startMs": Int(group.timeRange.start.seconds * 1000), "title": title]
    }
  }
}
