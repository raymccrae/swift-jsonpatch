//
//  JSONError.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import Foundation

public enum JSONError: Error {
    case invalidObjectType
    case invalidPointerSyntax
    case referencesNonexistentValue
    case patchTestFailed(path: String, expected: Any, found: Any?)
}
