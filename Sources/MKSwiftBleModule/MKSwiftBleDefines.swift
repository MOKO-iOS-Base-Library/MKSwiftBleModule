//
//  File.swift
//  MKSwiftBleModule
//
//  Created by aa on 2025/5/18.
//

import Foundation

// MARK: - 类型安全验证工具
public struct MKValidator {
    /// 验证非空字符串 (替代 MKValidStr)
    public static func isValidString(_ value: Any?) -> Bool {
        guard let str = value as? String else { return false }
        return !str.isEmpty
    }
    
    /// 验证非空字典 (替代 MKValidDict)
    public static func isValidDictionary(_ value: Any?) -> Bool {
        guard let dict = value as? [AnyHashable: Any] else { return false }
        return !dict.isEmpty
    }
    
    /// 验证非空数组 (替代 MKValidArray)
    public static func isValidArray(_ value: Any?) -> Bool {
        guard let arr = value as? [Any] else { return false }
        return !arr.isEmpty
    }
    
    /// 验证Data对象 (替代 MKValidData)
    public static func isValidData(_ value: Any?) -> Bool {
        value is Data
    }
}

// MARK: - 线程安全工具
public enum MKThreadUtils {
    /// 主线程安全执行 (替代 MKBLEBase_main_safe)
    @MainActor
    public static func runOnMain(_ block: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
    }
}

// MARK: - 扩展实现（更Swifty的用法）
extension Optional where Wrapped == String {
    /// 字符串有效性检查扩展
    var isValid: Bool {
        guard let str = self else { return false }
        return !str.isEmpty
    }
}

extension Optional where Wrapped: Collection {
    /// 集合类型有效性检查扩展
    var isValid: Bool {
        guard let collection = self else { return false }
        return !collection.isEmpty
    }
}

// MARK: - 使用示例
/*
// 1. 类型验证（两种方式任选）
let testStr: Any? = "hello"
print(MKValidator.isValidString(testStr))  // 函数式
print((testStr as? String)?.isValid ?? false)  // 扩展属性式

// 2. 主线程安全执行
MKThreadUtils.runOnMain {
    self.label.text = "Updated"
}
*/
