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
    
    init(_ ast: Structure, content: String, processed: Bool) {
        var comps = ast.name.components(separatedBy: CharacterSet(arrayLiteral: ":", "(", ")")).filter {!$0.isEmpty}
        let nameString = comps.removeFirst()
        self.content = content
        self.name = nameString
        self.type = ast.typeName == .unknownVal ? "" : ast.typeName
        self.staticKind = ast.isStaticMethod ? .static : ""
        self.processed = processed
        self.isInitializer = ast.isInitializer
        self.offset = ast.range.offset
        self.length = ast.range.length

        let paramDecls = ast.substructures.filter(path: \.isVarParameter)
        if paramDecls.count > 0 {
            assert(paramDecls.count == comps.count)
        }
        self.params = zip(paramDecls, comps).map { (argModel: Structure, argLabel: String) -> ParamModel in
            ParamModel(argModel, label: argLabel)
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
        self.handler = self.isInitializer ? nil :
                        ClosureModel(name: self.name,
                                    genericTypeParams: genericTypeParams,
                                    paramNames: paramNames,
                                    paramTypes: paramTypes,
                                    returnType: ast.typeName,
                                    staticKind: staticKind)
        self.accessControlLevelDescription = ast.accessControlLevelDescription
        self.attributes = ast.hasAvailableAttribute ? ast.extractAttributes(content, filterOn: SwiftDeclarationAttributeKind.available.rawValue) : []
    }
    
    var fullName: String {
        return self.name + self.signatureComponents.joined()
    }
    
    func name(by level: Int) -> String {
        let cap = min(level, self.signatureComponents.count)
        if cap <= 0 {
            return name
        }
        return name(by: cap-1) + self.signatureComponents[cap-1]
    }
    
    func render(with identifier: String, typeKeys: [String: String]? = nil) -> String? {
        if processed {
            return isInitializer ? nil : self.content.extract(offset: self.offset, length: self.length)
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
                                         handler: handler,
                                         typeKeys: typeKeys)
        return result
    }
}
