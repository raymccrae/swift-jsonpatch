//
//  NSArray+DeepCopy.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 13/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import Foundation

extension NSArray {

    func deepMutableCopy() -> NSMutableArray {
        let result = NSMutableArray(capacity: count)

        for element in self {
            switch element {
            case let array as NSArray:
                result.add(array.deepMutableCopy())
            case let dict as NSDictionary:
                result.add(dict.deepMutableCopy())
            case let str as NSMutableString:
                result.add(str.mutableCopy())
//            case let null as NSNull:
//                result.add(null)
            case let obj as NSObject:
                result.add(obj.copy())
            default:
                result.add(element)
            }
        }

        return result
    }

}
