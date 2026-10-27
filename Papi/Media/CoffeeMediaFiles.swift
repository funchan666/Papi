import Foundation
import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import AVFoundation
import ImageIO

struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at:received.file,to:target)
            return ImportedMovie(url:target)
        }
    }
}
enum CoffeeMedia {
    private static let imageCache: NSCache<NSString,UIImage> = {let cache=NSCache<NSString,UIImage>();cache.totalCostLimit=64*1024*1024;return cache}()
    @MainActor private static var posterTasks:[String:Task<UIImage?,Never>]=[:]
    @MainActor private static var activePosters=0
    @MainActor private static var posterWaiters:[CheckedContinuation<Void,Never>]=[]
    private static let collectionSession:URLSession = {
        let configuration=URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost=4
        configuration.timeoutIntervalForRequest=20
        configuration.timeoutIntervalForResource=30
        configuration.urlCache=URLCache(memoryCapacity:8*1024*1024,diskCapacity:32*1024*1024,diskPath:"PapiCollection")
        configuration.httpCookieStorage=nil
        configuration.httpShouldSetCookies=false
        return URLSession(configuration:configuration)
    }()
    static var root: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PapiMedia",isDirectory:true) }
    static func directory(_ guest: UUID) throws -> URL {
        let dir = root.appendingPathComponent(guest.uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        return dir
    }
    static func url(_ reference: String) -> URL? {
        let name=CoffeeArtwork.canonical(reference)
        if name.hasPrefix("local/") {
            let relative = String(name.dropFirst(6))
            guard !relative.contains(".."), relative.split(separator:"/").count == 2 else { return nil }
            let file = root.appendingPathComponent(relative)
            return FileManager.default.fileExists(atPath:file.path) ? file : nil
        }
        return CoffeeCollection.url(name)
    }
    static func image(_ reference: String) -> UIImage? {
        let name=CoffeeArtwork.canonical(reference)
        if let cached=imageCache.object(forKey:name as NSString) {return cached}
        if let url = url(name), name.hasPrefix("local/") {
            let file=isMovie(url) ? url.appendingPathExtension("poster.jpg"):url
            let image=UIImage(contentsOfFile:file.path)
            if let image {imageCache.setObject(image,forKey:name as NSString,cost:Int(image.size.width*image.size.height*4))}
            return image
        }
        if CoffeeCollection.entry(name) != nil {return nil}
        return UIImage(named:name)
    }
    private static func isMovie(_ url:URL)->Bool {
        UTType(filenameExtension:url.pathExtension)?.conforms(to:.movie) == true
    }
    @MainActor static func preparePoster(_ reference:String) async -> UIImage? {
        let name=CoffeeArtwork.canonical(reference)
        if let image=image(name) {return image}
        guard let file=url(name) else{return nil}
        if let task=posterTasks[name] {return await task.value}
        let task=Task<UIImage?,Never> {
            if !isMovie(file) {
                guard let remote=CoffeeCollection.url(name) else{return nil}
                do {
                    let (data,response)=try await collectionSession.data(from:remote)
                    guard let response=response as? HTTPURLResponse,response.statusCode==200,
                          response.url?.scheme=="https",response.url?.host==remote.host,
                          response.mimeType?.hasPrefix("image/")==true,data.count<=20_000_000 else{return nil}
                    let image=await Task.detached(priority:.utility) {downsample(data)}.value
                    if let image {cache(image,name:name)}
                    return image
                } catch {return nil}
            }
            await acquirePosterSlot()
            defer {releasePosterSlot()}
            let generator=AVAssetImageGenerator(asset:AVURLAsset(url:file))
            generator.appliesPreferredTrackTransform=true
            generator.maximumSize=CGSize(width:900,height:900)
            do {
                guard let image=await posterImage(generator) else{return nil}
                guard !Task.isCancelled,!file.isFileURL || FileManager.default.fileExists(atPath:file.path) else{return nil}
                if file.isFileURL,let data=image.jpegData(compressionQuality:0.85) {
                    try data.write(to:file.appendingPathExtension("poster.jpg"),options:[.atomic,.completeFileProtectionUnlessOpen])
                }
                cache(image,name:name)
                return image
            } catch {return nil}
        }
        posterTasks[name]=task
        let image=await task.value
        posterTasks.removeValue(forKey:name)
        return image
    }
    fileprivate static func downsample(_ data:Data)->UIImage? {
        guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let frame=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1600,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else{return nil}
        return UIImage(cgImage:frame)
    }
    private static func posterImage(_ generator:AVAssetImageGenerator) async -> UIImage? {
        await withTaskGroup(of:UIImage?.self) {group in
            group.addTask {
                do {let frame=try await generator.image(at:.zero);return UIImage(cgImage:frame.image)}
                catch {return nil}
            }
            group.addTask {
                do {try await Task.sleep(for:.seconds(20))} catch {return nil}
                generator.cancelAllCGImageGeneration()
                return nil
            }
            let image=await group.next() ?? nil
            group.cancelAll();generator.cancelAllCGImageGeneration()
            return image
        }
    }
    private static func cache(_ image:UIImage,name:String) {
        imageCache.setObject(image,forKey:name as NSString,cost:(image.cgImage?.bytesPerRow ?? 0)*(image.cgImage?.height ?? 0))
    }
    @MainActor private static func acquirePosterSlot() async {
        if activePosters<2 {activePosters+=1;return}
        await withCheckedContinuation {posterWaiters.append($0)}
    }
    @MainActor private static func releasePosterSlot() {
        if !posterWaiters.isEmpty {posterWaiters.removeFirst().resume()}
        else {activePosters=max(0,activePosters-1)}
    }
    static func saveImage(_ data: Data, guest: UUID) throws -> String {
        guard data.count <= 40_000_000, let image = UIImage(data:data), let jpeg = image.jpegData(compressionQuality:0.9) else { throw MediaError.invalid }
        let name = UUID().uuidString + ".jpg"
        let file = try directory(guest).appendingPathComponent(name)
        try jpeg.write(to:file,options:[.atomic,.completeFileProtectionUnlessOpen])
        return "local/\(guest.uuidString)/\(name)"
    }
    static func saveMovie(_ source: URL, guest: UUID) throws -> String {
        let values = try source.resourceValues(forKeys:[.fileSizeKey])
        guard (values.fileSize ?? Int.max) <= 150_000_000 else { throw MediaError.tooLarge }
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let name = UUID().uuidString + "." + ext
        let file = try directory(guest).appendingPathComponent(name)
        try FileManager.default.copyItem(at:source,to:file)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:file.path)
        return "local/\(guest.uuidString)/\(name)"
    }
    static func removeGuestDirectory(_ guest: UUID) throws {
        imageCache.removeAllObjects()
        let folder=root.appendingPathComponent(guest.uuidString)
        if FileManager.default.fileExists(atPath:folder.path) {try FileManager.default.removeItem(at:folder)}
    }
    enum MediaError: LocalizedError {
        case invalid, tooLarge
        var errorDescription: String? { self == .invalid ? "This image could not be opened. Choose another image under 40 MB." : "Choose a video smaller than 150 MB." }
    }
}

// Signed URLs and decoded images for private submissions stay in memory only.
struct PrivateSubmissionPhoto:View {
    let path:String
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.scenePhase) private var scenePhase
    @State private var image:UIImage?
    @State private var imageOwner:UUID?
    @State private var imagePath:String?
    private static let session:URLSession = {
        let config=URLSessionConfiguration.ephemeral
        config.urlCache=nil;config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage=nil;config.httpShouldSetCookies=false
        config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=30
        return URLSession(configuration:config)
    }()
    var body:some View {
        Group {
            if store.state.signedIn,scenePhase == .active,imageOwner==store.state.cloudAccountID,imagePath==path,let image {
                Image(uiImage:image).resizable().scaledToFill()
            } else {Image("emptyCup").resizable().scaledToFit().padding(8).background(Color.cream)}
        }.clipped().task(id:"\(store.state.cloudAccountID?.uuidString ?? "none")|\(path)|\(scenePhase == .active)|\(store.state.signedIn)") {
            image=nil;imageOwner=nil;imagePath=nil
            guard scenePhase == .active,store.state.signedIn,let account=store.state.cloudAccountID,
                  path.lowercased().hasPrefix(account.uuidString.lowercased()+"/") else{return}
            do {
                let url=try await CoffeeCloud.shared.mediaURL(path:path,account:account)
                guard url.scheme=="https",url.host=="cquoffowtjnxmgaxavym.supabase.co" else{return}
                let (data,response)=try await Self.session.data(from:url)
                guard let response=response as? HTTPURLResponse,response.statusCode==200,
                      response.url?.scheme=="https",response.url?.host==url.host,
                      response.mimeType?.hasPrefix("image/")==true,data.count<=40_000_000 else{return}
                let decoded=await Task.detached(priority:.utility){CoffeeMedia.downsample(data)}.value
                guard !Task.isCancelled,store.state.signedIn,store.state.cloudAccountID==account,scenePhase == .active else{return}
                image=decoded;imageOwner=account;imagePath=path
            } catch {return}
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var movie: Bool
    var completion: (Result<CameraOutput,Error>?) -> Void
    enum CameraOutput { case photo(Data), movie(URL) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = movie ? [UTType.movie.identifier] : [UTType.image.identifier]
        picker.videoMaximumDuration = 60
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Result<CameraOutput,Error>?) -> Void
        init(_ completion: @escaping (Result<CameraOutput,Error>?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]) {
            if let url = info[.mediaURL] as? URL { completion(.success(.movie(url))) }
            else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality:0.92) { completion(.success(.photo(data))) }
            else { completion(.failure(CoffeeMedia.MediaError.invalid)) }
        }
    }
}
