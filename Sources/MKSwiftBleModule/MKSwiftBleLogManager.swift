//
//  File.swift
//  MKSwiftBleModule
//
//  Created by aa on 2025/5/18.
//

import Foundation

public class MKSwiftBleLogManager {
    
    // MARK: - Private Properties
    
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    // MARK: - Public Methods
    
    /// Save data to local file with name "/fileName.txt" in Library/Caches directory
    /// - Parameters:
    ///   - fileName: Name of the file to save
    ///   - dataList: Array of strings to write
    /// - Returns: true if successful, false otherwise
    @discardableResult
    public static func saveData(fileName: String, dataList: [String]) -> Bool {
        guard !fileName.isEmpty, !dataList.isEmpty else {
            return false
        }
        
        let path = cachesDirectory()
        let localFileName = "/\(fileName).txt"
        let filePath = path + localFileName
        
        let fileExists = fileExists(atPath: filePath, isDirectory: false)
        if !fileExists {
            let createResult = createFile(atPath: path, fileName: localFileName)
            if !createResult {
                return false
            }
        }
        
        let fileManager = FileManager.default
        do {
            let fileAttributes = try fileManager.attributesOfItem(atPath: filePath)
            guard fileAttributes.count > 0 else {
                return false
            }
            
            let dateString = formatter.string(from: Date())
            
            // Synchronized block for thread-safe file writing
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }
            
            if let fileHandle = FileHandle(forUpdatingAtPath: filePath) {
                fileHandle.seekToEndOfFile()
                for tempData in dataList {
                    let stringToWrite = "\n\(dateString)  \(tempData)"
                    if let stringData = stringToWrite.data(using: .utf8) {
                        fileHandle.write(stringData)
                    }
                }
                fileHandle.closeFile()
                return true
            }
            return false
        } catch {
            return false
        }
    }
    
    /// Read data from local file with name "/fileName.txt"
    /// - Parameter fileName: Name of the file to read
    /// - Returns: Data object if successful, nil otherwise
    public static func readData(fileName: String) -> Data? {
        let path = cachesDirectory()
        let localFileName = "/\(fileName).txt"
        let filePath = path + localFileName
        
        guard let fileString = readFile(atPath: filePath), !fileString.isEmpty else {
            return nil
        }
        
        return fileString.data(using: .utf8)
    }
    
    /// Delete local file with name "/fileName.txt"
    /// - Parameter fileName: Name of the file to delete
    public static func deleteLog(fileName: String) -> Bool {
        let path = cachesDirectory()
        let localFileName = "/\(fileName).txt"
        let filePath = path + localFileName
        return deleteFile(atPath: filePath)
    }
    
    // MARK: - Private Methods
    
    private static func cachesDirectory() -> String {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).last!
    }
    
    private static func fileExists(atPath path: String, isDirectory: Bool) -> Bool {
        var isDir: ObjCBool = ObjCBool(isDirectory)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    }
    
    private static func createFile(atPath path: String, fileName: String) -> Bool {
        let fileManager = FileManager.default
        let newFilePath = (path as NSString).appendingPathComponent(fileName)
        return fileManager.createFile(atPath: newFilePath, contents: nil, attributes: nil)
    }
    
    private static func deleteFile(atPath path: String) -> Bool {
        do {
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
    
    private static func readFile(atPath path: String) -> String? {
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
