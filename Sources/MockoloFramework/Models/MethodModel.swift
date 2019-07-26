//
//  Copyright (c) 2018. Uber Technologies
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
import SourceKittenFramework

struct MethodModel: Model {
    var filePath: String
    var name: String
    var type: String
    var offset: Int64
    let length: Int64
    let accessControlLevelDescription: String
    let attributes: [String]
    let staticKind: String
    let content: String
    let genericTypeParams: [ParamModel]
    let params: [ParamModel]
    let handler: ClosureModel?
    let processed: Bool
    let signatureComponents: [String]
    let isInitializer: Bool
    let suffix: String
    let cacheKey: NSString

    var modelType: ModelType {
        return .method
    }
    
    init(_ ast: Structure, filepath: String, content: String, processed: Bool) {
        // This will split func signature into name and the rest (params, return type). In case it's a generic func,
        // its type parameters will be in its substrctures (and < > are omitted in the func ast.name), so it will only
        // give the name part that we expect.
        var comps = ast.name.components(separatedBy: CharacterSet(arrayLiteral: ":", "(", ")")).filter {!$0.isEmpty}
        let nameString = comps.removeFirst()
        self.filePath = filepath

        self.content = content
        self.name = nameString
        self.type = ast.typeName == .unknownVal ? "" : ast.typeName
        self.staticKind = ast.isStaticMethod ? .static : ""
        self.processed = processed
        self.isInitializer = ast.isInitializer
        self.offset = ast.range.offset
        self.length = ast.range.length

        let paramDecls = ast.substructures.filter(path: \.isVarParameter)
        assert(paramDecls.count == comps.count)
        
        let zippedParams = zip(paramDecls, comps)
        self.params = zippedParams.map { (argAst: Structure, argLabel: String) -> ParamModel in
            ParamModel(argAst, label: argLabel, isInitializer: ast.isInitializer)
        }

        let paramLabels = self.params.map {$0.label != "_" ? $0.label : ""}
        let paramNames = paramDecls.map(path: \.name)
        let paramTypes = paramDecls.map(path: \.typeName)
        self.genericTypeParams = ast.substructures
            .filter(path: \.isGenericTypeParam)
            .map { (arg: Structure) -> ParamModel in
                ParamModel(arg, label: arg.name, isGeneric: true)
        }
        let genericNameTypes = self.genericTypeParams.map { $0.name.capitlizeFirstLetter + $0.type.displayableForType }
        var args = zip(paramLabels, paramNames).compactMap { (argLabel: String, argName: String) -> String? in
            let val = argLabel.isEmpty ? argName : argLabel
            if val.count < 2 || !nameString.lowercased().hasSuffix(val.lowercased()) {
                return val.capitlizeFirstLetter
            }
            return nil
        }
        args.append(contentsOf: genericNameTypes)
        args.append(contentsOf: paramTypes.map(path: \.displayableForType))
        let capped = String.Index(encodedOffset: min(self.type.displayableForType.count, 32))
        args.append(self.type.displayableForType.substring(to: capped))
        
        // Used to make the underlying function handler var name unique by providing args
        // that can be appended to the name
        self.signatureComponents = args.filter{ arg in !arg.isEmpty }

        // Sourcekit structure api doesn't provide info on throws/rethrows, so manually parse it here
        let suffixOffset = ast.nameOffset + ast.nameLength + 1
        let suffixLen = ast.offset + ast.length - suffixOffset
        if suffixLen > 0, suffixOffset > ast.bodyOffset - 1{
            let suffixPart = content.extract(offset: suffixOffset, length: suffixLen).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if suffixPart.hasPrefix("\(String.rethrows)") {
                self.suffix = String.rethrows
            } else if suffixPart.hasPrefix("\(String.throws)") {
                self.suffix = String.throws
            } else {
                self.suffix = ""
            }
        } else {
            self.suffix = ""
        }

        self.handler = self.isInitializer ? nil :
                        ClosureModel(name: name,
                                    genericTypeParams: genericTypeParams,
                                    paramNames: paramNames,
                                    paramTypes: paramTypes,
                                    suffix: suffix,
                                    returnType: ast.typeName,
                                    staticKind: staticKind)
        self.accessControlLevelDescription = ast.accessControlLevelDescription
        self.attributes = ast.hasAvailableAttribute ? ast.extractAttributes(content, filterOn: SwiftDeclarationAttributeKind.available.rawValue) : []
        self.cacheKey = NSString(string: "\(filePath)_\(name)_\(type)_\(offset)_\(length)")

    }
    
    var fullName: String {
        return self.name + self.signatureComponents.joined()
    }
    
    func name(by level: Int) -> String {
        if level <= 0 {
            return name
        }
        let diff = level - self.signatureComponents.count
        let postfix = diff > 0 ? String(diff) : self.signatureComponents[level - 1]
        return name(by: level - 1) + postfix
    }

    
    func render(with identifier: String, typeKeys: [String: String]? = nil) -> String? {
        if processed {
            if isInitializer {
                return nil
            }
            
            if cacheKey.cached() == nil {
                if let utf8data = content.data(using: .utf8) {
                    cacheKey.cache(with: utf8data)
                }
            }

            let utf8data = cacheKey.cached()
            let ret = utf8data?.extract(offset: self.offset, length: self.length)
            return ret
        }
    
        let returnType = type != .unknownVal ? type : ""
        let result = applyMethodTemplate(name: name,
                                         identifier: identifier,
                                         isInitializer: isInitializer,
                                         genericTypeParams: genericTypeParams,
                                         params: params,
                                         returnType: returnType,
                                         staticKind: staticKind,
                                         accessControlLevelDescription: accessControlLevelDescription,
                                         suffix: suffix,
                                         handler: handler,
                                         typeKeys: typeKeys)
        return result
    }
    
    
}

