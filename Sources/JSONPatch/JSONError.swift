//
//  JSONError.swift
//  JSONPatch
//
//  Created by Raymond Mccrae on 11/11/2018.
//  Copyright © 2018 Raymond McCrae. All rights reserved.
//

import Foundation

enum JSONError: Error {
    case invalidPointerSyntax
    case referencesNonexistentValue
}
