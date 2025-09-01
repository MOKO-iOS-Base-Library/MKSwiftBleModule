//
//  File.swift
//  MKSwiftBleModule
//
//  Created by aa on 2025/5/18.
//

import Foundation

public extension String {
    // MARK: - Size Calculations
    
    func bleSubstring(from location: Int, length: Int) -> String {
        guard location >= 0, location < self.count else {
            return ""
        }
        
        let startIndex = self.index(self.startIndex, offsetBy: location)
        let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
        
        return String(self[startIndex..<endIndex])
    }
}

public enum MKSwiftBleError: LocalizedError {
    case unknown
    case bluetoothPowerOff
    case connectFailed
    case connecting
    case protocolError
    case paramsError
    case setParamsError
    case timeout
    
    var localizedDescription: String {
        switch self {
        case .unknown:
            return "Unknow error"
        case .bluetoothPowerOff:
            return "Mobile phone bluetooth is currently unavailable"
        case .connectFailed:
            return "Connect Failed"
        case .connecting:
            return "The device is connectting"
        case .protocolError:
            return "The parameters passed in must conform to the protocol"
        case .paramsError:
            return "Params error"
        case .setParamsError:
            return "Set parameter error"
        case .timeout:
            return "Connect timeout"
        }
    }
}

public class MKSwiftBleSDKAdopter {
    // MARK: - Hex/Decimal Conversions
    
    /// 十六进制字符串转十进制正整数
    /// - Parameters:
    ///   - content: 十六进制字符串
    ///   - range: 要转换的conten范围
    /// - Returns: 十进制正整数
    public class func getDecimalWithHex(_ content: String, range: NSRange) -> Int {
        guard MKValidator.isValidString(content) else { return 0 }
        
        for i in 0..<content.count {
            let char = String(content[content.index(content.startIndex, offsetBy: i)])
            if !checkHexCharacter(char) {
                return 0
            }
        }
        
        if range.location > content.count - 1 || range.length > content.count || (range.location + range.length > content.count) {
            return 0
        }
        
        let substring = (content as NSString).substring(with: range)
        return Int(strtoul(substring, nil, 16))
    }
    
    /// 十六进制字符串转十进制正整数字符串
    /// - Parameters:
    ///   - content: 十六进制字符串
    ///   - range: 要转换的conten范围
    /// - Returns: 十进制正整数字符串
    public class func getDecimalStringWithHex(_ content: String, range: NSRange) -> String {
        let decimalValue = getDecimalWithHex(content, range: range)
        return "\(decimalValue)"
    }
    
    /// 十六进制的Data转换为十进制正整数
    /// - Parameters:
    ///   - data: 十六进制的Data
    ///   - range: 要转换的data范围
    /// - Returns: 十进制正整数
    public class func getDecimalFromData(_ data: Data, range: Range<Int>) -> Int {
        guard !data.isEmpty else { return 0 }
        guard range.lowerBound >= 0, range.upperBound <= data.count else { return 0 }
        
        let subdata = data.subdata(in: range)
        var decimalValue = 0
        
        for byte in subdata {
            decimalValue = decimalValue << 8 + Int(byte)
        }
        
        return decimalValue
    }
    
    /// 十六进制的Data转换为十进制正整数字符串
    /// - Parameters:
    ///   - data: 十六进制的Data
    ///   - range: 要转换的data范围
    /// - Returns: 十进制正整数字符串
    public class func getDecimalStringFromData(_ data: Data, range: Range<Int>) -> String {
        let decimalValue = getDecimalFromData(data, range: range)
        return "\(decimalValue)"
    }
    
    /// 有符号10进制转16进制字符串
    /// - Parameter number: 带符号的10进制数
    /// - Returns: 十六进制字符串
    public class func hexStringFromSignedNumber(_ number: Int) -> String {
        var tempNumber = String(format: "%lX", number)
        if tempNumber.count == 1 {
            tempNumber = "0" + tempNumber
        }
        let data = stringToData(tempNumber)
        let resultData = data.subdata(in: data.count-1..<data.count)
        return hexStringFromData(resultData)
    }
    
    /// 带符号的十六进制字符串转十进制数字
    /// - Parameter content: 带符号的十六进制字符串
    /// - Returns: 转换的十进制数据
    public class func signedHexTurnToInt(_ content: String) -> Int {
        guard !content.isEmpty else { return 0 }
        
        // 将十六进制字符串转换为 UInt64（无符号）
        guard let unsignedValue = UInt64(content, radix: 16) else { return 0 }
        
        let bitLength = content.count * 4 // 每个十六进制字符占4位
        let maxUnsignedValue = UInt64(1) << bitLength
        
        // 检查最高位是否为1（负数）
        if unsignedValue & (1 << (bitLength - 1)) != 0 {
            // 负数：进行补码转换
            return Int(Int64(unsignedValue) - Int64(maxUnsignedValue))
        } else {
            // 正数：直接转换
            return Int(unsignedValue)
        }
    }
    
    /// 带符号的十六进制的Data转换为十进制数字
    /// - Parameter data: 带符号的十六进制的Data
    /// - Returns: 十进制数字
    public class func signedDataTurnToInt(_ data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        
        switch data.count {
        case 1:
            return Int(Int8(bitPattern: data[0]))
        case 2:
            let value = data.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            return Int(Int16(bitPattern: value))
        case 4:
            let value = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            return Int(Int32(bitPattern: value))
        case 8:
            let value = data.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            return Int(Int64(bitPattern: value))
        default:
            // 对于其他长度，使用通用方法
            return signedDataTurnToIntGeneric(data)
        }
    }
    
    public class func hexStringFromData(_ sourceData: Data) -> String {
        guard MKValidator.isValidData(sourceData) else { return "" }
        
        var hexStr = ""
        let bytes = [UInt8](sourceData)
        
        for byte in bytes {
            let newHexStr = String(format: "%x", byte & 0xff)
            hexStr += newHexStr.count == 1 ? "0\(newHexStr)" : newHexStr
        }
        
        return hexStr
    }
    
    /// Converts a hexadecimal string to `Data`.
    /// - Note: Supports both even and odd-length strings (e.g., "A1B2" or "ABC").
    /// - Returns: Empty `Data` if the input string is invalid.
    public class func stringToData(_ hexString: String) -> Data {
        guard MKValidator.isValidString(hexString) else { return Data() }
        
        let chunkSize = hexString.count % 2 == 0 ? 2 : 1
        var data = Data()
        data.reserveCapacity((hexString.count + chunkSize - 1) / chunkSize)
        
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let endIndex = hexString.index(index, offsetBy: chunkSize, limitedBy: hexString.endIndex) ?? hexString.endIndex
            let substring = String(hexString[index..<endIndex])
            
            if let byte = UInt8(substring, radix: 16) {
                data.append(byte)
            }
            index = endIndex
        }
        
        return data
    }
    
    // MARK: - Validation Methods
    
    public class func checkHexCharacter(_ character: String) -> Bool {
        guard MKValidator.isValidString(character) else { return false }
        
        let regex = "[a-fA-F0-9]*"
        let pred = NSPredicate(format: "SELF MATCHES %@", regex)
        return pred.evaluate(with: character)
    }
    
    public class func binaryByhex(_ hex: String) -> String {
        guard MKValidator.isValidString(hex), checkHexCharacter(hex) else { return "" }
        
        var hexString = hex
        if hex.count % 2 != 0 {
            hexString = String(repeating: "0", count: 2 - hex.count % 2) + hex
        }
        
        let hexDic: [String: String] = [
            "0": "0000", "1": "0001", "2": "0010",
            "3": "0011", "4": "0100", "5": "0101",
            "6": "0110", "7": "0111", "8": "1000",
            "9": "1001", "A": "1010", "a": "1010",
            "B": "1011", "b": "1011", "C": "1100",
            "c": "1100", "D": "1101", "d": "1101",
            "E": "1110", "e": "1110", "F": "1111",
            "f": "1111"
        ]
        
        var binaryString = ""
        for char in hexString {
            if let binary = hexDic[String(char)] {
                binaryString += binary
            }
        }
        
        return binaryString
    }
    
    public class func asciiString(_ content: String) -> Bool {
        let strlen = content.count
        let datalen = content.data(using: .utf8)?.count ?? 0
        return strlen == datalen
    }
    
    public class func isUUIDString(_ uuid: String) -> Bool {
        let uuidPatternString = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        let regex = try? NSRegularExpression(pattern: uuidPatternString, options: .caseInsensitive)
        let numberOfMatches = regex?.numberOfMatches(in: uuid, options: [], range: NSRange(location: 0, length: uuid.count)) ?? 0
        return numberOfMatches > 0
    }
    
    // MARK: - Binary/Hex Conversions
    
    public class func getHexByBinary(_ binary: String) -> String {
        guard MKValidator.isValidString(binary), checkHexCharacter(binary) else { return "" }
        
        let binaryDic: [String: String] = [
            "0000": "0", "0001": "1", "0010": "2",
            "0011": "3", "0100": "4", "0101": "5",
            "0110": "6", "0111": "7", "1000": "8",
            "1001": "9", "1010": "A", "1011": "B",
            "1100": "C", "1101": "D", "1110": "E",
            "1111": "F"
        ]
        
        var binaryString = binary
        if binary.count % 8 != 0 {
            binaryString = String(repeating: "0", count: 8 - binary.count % 8) + binary
        }
        
        let totalNum = binaryString.count / 8
        var tempString = ""
        
        for j in 0..<totalNum {
            var hex = ""
            let startIndex = binaryString.index(binaryString.startIndex, offsetBy: j * 8)
            let endIndex = binaryString.index(startIndex, offsetBy: 8)
            let tempBinary = String(binaryString[startIndex..<endIndex])
            
            var i = 0
            while i < tempBinary.count {
                let start = tempBinary.index(tempBinary.startIndex, offsetBy: i)
                let end = tempBinary.index(start, offsetBy: 4)
                let key = String(tempBinary[start..<end])
                if let value = binaryDic[key] {
                    hex += value
                }
                i += 4
            }
            
            tempString += hex
        }
        
        return tempString
    }
    
    public class func fetchHexValue(_ value: Int, byteLen len: Int) -> String {
        if len <= 0 { return "" }
        
        var valueString = String(format: "%1lx", value)
        let needLen = 2 * len - valueString.count
        
        if needLen > 0 {
            valueString = String(repeating: "0", count: needLen) + valueString
        }
        
        return valueString
    }
    
    // MARK: - Private Methods
    
    private class func signedDataTurnToIntGeneric(_ data: Data) -> Int {
        var unsignedValue: UInt64 = 0
        let bitLength = data.count * 8
        
        // 大端序处理
        for byte in data {
            unsignedValue = unsignedValue << 8 + UInt64(byte)
        }
        
        let signBitMask: UInt64 = 1 << (bitLength - 1)
        
        if unsignedValue & signBitMask == 0 {
            // 正数
            return Int(unsignedValue)
        } else {
            // 负数：计算补码
            let maxValue: UInt64 = 1 << bitLength
            return Int(Int64(unsignedValue) - Int64(maxValue))
        }
    }
    
    private class func numberHexString(_ aHexString: String) -> NSNumber {
        guard !aHexString.isEmpty else { return 0 }
        
        var longlongValue: UInt64 = 0
        Scanner(string: aHexString).scanHexInt64(&longlongValue)
        return NSNumber(value: longlongValue)
    }
    
    private class func headString(_ headStr: String, trilString trilStr: String, strLenth lenth: Int) -> String {
        guard !headStr.isEmpty, !trilStr.isEmpty else { return "" }
        
        var string = "0x\(headStr)"
        for _ in 0..<(lenth * 2 - 1) {
            string += trilStr
        }
        return string
    }
}
