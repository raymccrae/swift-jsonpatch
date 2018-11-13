//
//  NSDictionary+DeepCopy.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 13/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import Foundation

extension NSDictionary {

    func deepMutableCopy() -> NSMutableDictionary {
        let result = NSMutableDictionary()

        self.enumerateKeysAndObjects { (key, value, stop) in
            switch value {
            case let array as NSArray:
                result[key] = array.deepMutableCopy()
            case let dict as NSDictionary:
                result[key] = dict.deepMutableCopy()
            case let str as NSMutableString:
                result[key] = str
//            case let null as NSNull:
//                result[key] = null
            case let obj as NSObject:
                result[key] = obj.copy()
            default:
                result[key] = value
            }
        }

        return result
    }

}
