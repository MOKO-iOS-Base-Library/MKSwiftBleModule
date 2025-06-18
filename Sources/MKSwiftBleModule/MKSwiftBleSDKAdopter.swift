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

public enum MKSwiftBleError: Error {
    case bluetoothPowerOff
    case connectFailed
    case connecting
    case protocolError
    case paramsError
    case setParamsError
    
    var localizedDescription: String {
        switch self {
        case .bluetoothPowerOff:
            return "Mobile phone bluetooth is currently unavailable"
        case .connectFailed:
            return "Connect Failed"
        case .connecting:
            return "The devices are connectting"
        case .protocolError:
            return "The parameters passed in must conform to the protocol"
        case .paramsError:
            return "Params error"
        case .setParamsError:
            return "Set parameter error"
        }
    }
}

public class MKSwiftBleSDKAdopter {
    // MARK: - Hex/Decimal Conversions
    
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
    
    public class func getDecimalStringWithHex(_ content: String, range: NSRange) -> String {
        let decimalValue = getDecimalWithHex(content, range: range)
        return "\(decimalValue)"
    }
    
    public class func hexStringFromSignedNumber(_ number: Int) -> String {
        var tempNumber = String(format: "%lX", number)
        if tempNumber.count == 1 {
            tempNumber = "0" + tempNumber
        }
        let data = stringToData(tempNumber)
        let resultData = data.subdata(in: data.count-1..<data.count)
        return hexStringFromData(resultData)
    }
    
    public class func signedHexTurnString(_ content: String) -> NSNumber {
        guard MKValidator.isValidString(content) else { return 0 }
        
        let tempData = stringToData(content)
        let length = tempData.count
        let maxHexString = headString("F", trilString: "F", strLenth: length)
        let centerHexString = headString("8", trilString: "0", strLenth: length)
        
        if (numberHexString(content).int64Value - numberHexString(centerHexString).int64Value) < 0 {
            return numberHexString(content)
        }
        
        let maxValue = numberHexString(content).int64Value
        let minValue = numberHexString(maxHexString).int64Value
        return NSNumber(value: maxValue - minValue - 1)
    }
    
    // MARK: - CRC and Data Conversions
    
    public class func getCrc16VerifyCode(_ data: Data) -> Data {
        guard MKValidator.isValidData(data) else { return Data() }
        
        var crcWord: UInt16 = 0xffff
        let bytes = [UInt8](data)
        
        for byte in bytes {
            crcWord ^= UInt16(byte) & 0x00ff
            for _ in 0..<8 {
                if (crcWord & 0x0001) == 1 {
                    crcWord >>= 1
                    crcWord ^= 0xA001
                } else {
                    crcWord >>= 1
                }
            }
        }
        
        let crcL = UInt8(0xff & (crcWord >> 8))
        let crcH = UInt8(0xff & crcWord)
        return Data([crcH, crcL])
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
    
    public class func stringToData(_ dataString: String) -> Data {
        guard MKValidator.isValidString(dataString) else { return Data() }
        
        var hexData = Data()
        var range: NSRange
        
        if dataString.count % 2 == 0 {
            range = NSRange(location: 0, length: 2)
        } else {
            range = NSRange(location: 0, length: 1)
        }
        
        var index = range.location
        while index < dataString.count {
            let endIndex = min(index + range.length, dataString.count)
            let hexCharStr = (dataString as NSString).substring(with: NSRange(location: index, length: endIndex - index))
            
            var anInt: UInt32 = 0
            Scanner(string: hexCharStr).scanHexInt32(&anInt)
            
            var intValue = UInt8(anInt)
            hexData.append(&intValue, count: 1)
            
            index += range.length
            range.length = 2
        }
        
        return hexData
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
    
    public class func fetchHexValue(_ value: UInt, byteLen len: Int) -> String {
        if len <= 0 { return "" }
        
        var valueString = String(format: "%1lx", value)
        let needLen = 2 * len - valueString.count
        
        if needLen > 0 {
            valueString = String(repeating: "0", count: needLen) + valueString
        }
        
        return valueString
    }
    
    // MARK: - Private Methods
    
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
