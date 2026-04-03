//
//  Bundle.swift
//  JSONPatchTests
//
//  Created by Raymond Mccrae on 19/11/2018.
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

extension Bundle {
    static let test: BundleProxy = BundleProxy()
}

struct BundleProxy {
    private let testDirURL: URL
    
    init() {
        // Try multiple strategies to find the test directory
        
        // Strategy 1: Use #file to determine the bundle directory  
        let sourceFileURL = URL(fileURLWithPath: #file)
        let sourceDir = sourceFileURL.deletingLastPathComponent()
        
        // Strategy 2: Check current working directory
        let cwd = FileManager.default.currentDirectoryPath
        let cwdURL = URL(fileURLWithPath: cwd)
        
        // Strategy 3: Check relative paths that might exist
        // For SPM resources copied to build directory
        let possibleDirs = [
            sourceDir,  // Source directory
            cwdURL,  // Current working directory
            cwdURL.appendingPathComponent("JSONPatchTests"),
            cwdURL.appendingPathComponent("Tests/JSONPatchTests"),
        ]
        
        // Find the first directory that contains test resources
        for dir in possibleDirs {
            let testFilePath = dir.appendingPathComponent("tests.json").path
            if FileManager.default.fileExists(atPath: testFilePath) {
                self.testDirURL = dir
                return
            }
        }
        
        // If nothing worked, default to source directory
        self.testDirURL = sourceDir
    }
    
    func url(forResource name: String?, withExtension ext: String?) -> URL? {
        return url(forResource: name, withExtension: ext, subdirectory: nil)
    }
    
    func url(forResource name: String?, withExtension ext: String?, subdirectory subpath: String?) -> URL? {
        var url = testDirURL
        if let subpath = subpath {
            url.appendPathComponent(subpath)
        }
        if let name = name {
            url.appendPathComponent(name)
        }
        if let ext = ext {
            url.appendPathExtension(ext)
        }
        
        // Check if the resource exists at the computed path
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        
        return nil
    }
}
