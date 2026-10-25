//
//  NSArray+DeepCopy.swift
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

extension NSArray {

    // Corelibs Foundation's public accessor bridges nested Foundation objects to
    // Swift values. Read the retained object so mutations keep their identity.
    func jsonObject(at index: Int) -> Any {
        #if os(Linux)
        let array = unsafeBitCast(self, to: CFArray.self)
        return Unmanaged<AnyObject>.fromOpaque(CFArrayGetValueAtIndex(array, index)).takeUnretainedValue()
        #else
        return object(at: index)
        #endif
    }

    func deepMutableCopy() -> NSMutableArray {
        let result = NSMutableArray(capacity: count)

        for index in 0..<count {
            let element = jsonObject(at: index)
            switch element {
            case let array as NSArray:
                result.add(array.deepMutableCopy())
            case let dict as NSDictionary:
                result.add(dict.deepMutableCopy())
            case let str as NSMutableString:
                result.add(str.mutableCopy())
            case let obj as NSObject:
                result.add(obj.copy())
            default:
                result.add(element)
            }
        }

        return result
    }

}
