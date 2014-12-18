//
//  Copyright (c) 2014 Zalando SE. All rights reserved.
//

import Foundation
import UIKit

public class DiskStorage: Storage {

    let fileManager: NSFileManager
    let storagePath: String
    let storageQueue: dispatch_queue_t

    public var maxAge: NSTimeInterval = 60 * 60 * 24 * 7

    public class var sharedStorage: DiskStorage {

        struct Singleton {
            static let instance = DiskStorage()
        }

        return Singleton.instance
    }

    public convenience init() {
        self.init(name: "default")
    }

    public init(name: String) {
        storageQueue = dispatch_queue_create("de.zalando.MapleBacon.Storage", DISPATCH_QUEUE_SERIAL)

        let paths = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true)
        storagePath = (paths.first as NSString).stringByAppendingPathComponent("de.zalando.MapleBacon.\(name)")

        fileManager = NSFileManager.defaultManager()
        fileManager.createDirectoryAtPath(storagePath, withIntermediateDirectories: true, attributes: nil, error: nil)
    }

    public func storeImage(image: UIImage, var data: NSData?, forKey key: String) {
        dispatch_async(storageQueue) {
            if (data == nil) {
                data = UIImagePNGRepresentation(image)
            }
            self.fileManager.createFileAtPath(self.defaultStoragePath(forKey: key), contents: data!, attributes: nil)
            self.pruneStorage()
        }
    }

    public func pruneStorage() {
        dispatch_async(storageQueue) {
            if let directoryURL = NSURL(fileURLWithPath: self.storagePath, isDirectory: true) {
                if let enumerator = self.fileManager.enumeratorAtURL(directoryURL,
                        includingPropertiesForKeys: [NSURLIsDirectoryKey, NSURLContentModificationDateKey],
                        options: .SkipsHiddenFiles,
                        errorHandler: nil) {
                    self.deleteExpiredFiles(self.expiredFiles(usingEnumerator: enumerator))
                }
            }
        }
    }

    private func expiredFiles(usingEnumerator enumerator: NSDirectoryEnumerator) -> [NSURL] {
        let expirationDate = NSDate(timeIntervalSinceNow: -maxAge)
        var expiredFiles = [NSURL]()
        while let fileURL = enumerator.nextObject() as? NSURL {
            if self.isDirectory(fileURL) {
                enumerator.skipDescendants()
                continue
            }
            if let modificationDate = self.modificationDate(fileURL) {
                if modificationDate.laterDate(expirationDate) == expirationDate {
                    expiredFiles.append(fileURL)
                }
            }
        }
        return expiredFiles
    }

    private func isDirectory(fileURL: NSURL) -> Bool {
        var isDirectoryResource: AnyObject?
        fileURL.getResourceValue(&isDirectoryResource, forKey: NSURLIsDirectoryKey, error: nil)
        if let isDirectory = isDirectoryResource as? NSNumber {
            return isDirectory.boolValue
        }
        return false
    }

    private func modificationDate(fileURL: NSURL) -> NSDate? {
        var modificationDateResource: AnyObject?
        fileURL.getResourceValue(&modificationDateResource, forKey: NSURLContentModificationDateKey, error: nil)
        return modificationDateResource as? NSDate
    }

    private func deleteExpiredFiles(files: [NSURL]) {
        for file in files {
            fileManager.removeItemAtURL(file, error: nil)
        }
    }

    public func image(forKey key: String) -> UIImage? {
        if let data = NSData(contentsOfFile: defaultStoragePath(forKey: key)) {
            return UIImage.imageWithData(data)
        }
        return nil
    }

    private func defaultStoragePath(forKey key: String) -> String {
        return storagePath(forKey: key, inPath: storagePath)
    }

    private func storagePath(forKey key: String, inPath path: String) -> String {
        return (path as NSString).stringByAppendingPathComponent(key.djb2Hash())
    }

    public func removeImage(forKey key: String) {
        dispatch_async(storageQueue) {
            self.fileManager.removeItemAtPath(self.defaultStoragePath(forKey: key), error: nil)
            return
        }
    }

    public func clearStorage() {
        dispatch_async(storageQueue) {
            self.fileManager.removeItemAtPath(self.storagePath, error: nil)
            self.fileManager.createDirectoryAtPath(self.storagePath, withIntermediateDirectories: true, attributes: nil,
                    error: nil)
        }
    }

}

extension String {

    func djb2Hash() -> String {
        let characters = Array(self)
        return "\(characters.reduce(5381, { (($0 << 5) &+ 1) &+ $1.codePoint() } ))"
    }

}

extension Character {

    func codePoint() -> Int {
        let scalars = String(self).unicodeScalars
        return Int(scalars[scalars.startIndex].value)
    }

}
