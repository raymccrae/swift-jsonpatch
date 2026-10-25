//
//  NSDictionary+DeepCopy.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 13/11/2018.
//  Copyright © 2018 Raymond McCrae.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import CoreFoundation

extension NSDictionary {

    func jsonObject(forKey key: Any) -> Any? {
        #if os(Linux)
        let dictionary = unsafeBitCast(self, to: CFDictionary.self)
        let object = key as AnyObject
        return withExtendedLifetime(object) {
            guard let pointer = CFDictionaryGetValue(dictionary, Unmanaged.passUnretained(object).toOpaque()) else {
                return nil
            }
            return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        }
        #else
        return object(forKey: key)
        #endif
    }

    func deepMutableCopy() -> NSMutableDictionary {
        let result = NSMutableDictionary()
        for key in allKeys {
            guard let value = jsonObject(forKey: key) else { continue }
            let copy: Any
            switch value {
            case let array as NSArray:
                copy = array.deepMutableCopy()
            case let dict as NSDictionary:
                copy = dict.deepMutableCopy()
            case let str as NSMutableString:
                copy = str.mutableCopy()
            case let obj as NSObject:
                copy = obj.copy()
            default:
                copy = value
            }
            #if os(Linux)
            result.setObject(copy, forKey: (key as? NSString) ?? String(describing: key) as NSString)
            #else
            result[key] = copy
            #endif
        }
        return result
    }
}
