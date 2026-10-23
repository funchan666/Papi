import Foundation
import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import AVFoundation

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
        if CoffeeArtwork.isFilm(name) {
            return Bundle.main.url(forResource:name,withExtension:"mp4",subdirectory:"Media") ?? Bundle.main.url(forResource:name,withExtension:"mp4")
        }
        return nil
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
        if CoffeeArtwork.isFilm(name) {
            let url = Bundle.main.url(forResource:name,withExtension:"jpg",subdirectory:"Media") ?? Bundle.main.url(forResource:name,withExtension:"jpg")
            let image=url.flatMap { UIImage(contentsOfFile:$0.path) }
            if let image {imageCache.setObject(image,forKey:name as NSString,cost:Int(image.size.width*image.size.height*4))}
            return image
        }
        return UIImage(named:name)
    }
    private static func isMovie(_ url:URL)->Bool {
        UTType(filenameExtension:url.pathExtension)?.conforms(to:.movie) == true
    }
    @MainActor static func preparePoster(_ name:String) async -> UIImage? {
        if let image=image(name) {return image}
        guard name.hasPrefix("local/"),let file=url(name),isMovie(file) else{return nil}
        if let task=posterTasks[name] {return await task.value}
        let task=Task<UIImage?,Never> {
            let generator=AVAssetImageGenerator(asset:AVURLAsset(url:file))
            generator.appliesPreferredTrackTransform=true
            generator.maximumSize=CGSize(width:900,height:900)
            do {
                let frame=try await generator.image(at:.zero)
                guard !Task.isCancelled,FileManager.default.fileExists(atPath:file.path) else{return nil}
                let image=UIImage(cgImage:frame.image)
                if let data=image.jpegData(compressionQuality:0.85) {
                    try data.write(to:file.appendingPathExtension("poster.jpg"),options:[.atomic,.completeFileProtectionUnlessOpen])
                }
                imageCache.setObject(image,forKey:name as NSString,cost:Int(image.size.width*image.size.height*4))
                return image
            } catch {return nil}
        }
        posterTasks[name]=task
        let image=await task.value
        posterTasks.removeValue(forKey:name)
        return image
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
