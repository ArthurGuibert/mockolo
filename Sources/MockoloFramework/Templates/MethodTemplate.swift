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

func applyMethodTemplate(name: String,
                         identifier: String,
                         isInitializer: Bool,
                         isSubscript: Bool,
                         genericTypeParams: [ParamModel],
                         params: [ParamModel],
                         returnType: Type,
                         staticKind: String,
                         accessControlLevelDescription: String,
                         suffix: String,
                         handler: ClosureModel?,
                         typeKeys: [String: String]?) -> String {
    var template = ""
    
    let returnTypeName = returnType.isUnknown ? "" : returnType.typeName

    let acl = accessControlLevelDescription.isEmpty ? "" : accessControlLevelDescription+" "
    let genericTypeDeclsStr = genericTypeParams.compactMap {$0.render(with: "")}.joined(separator: ", ")
    let genericTypesStr = genericTypeDeclsStr.isEmpty ? "" : "<\(genericTypeDeclsStr)>"
    let paramDeclsStr = params.compactMap{$0.render(with: "")}.joined(separator: ", ")

    if isInitializer {
        let paramsAssign = params.map { param in
            return """
                self.\(param.name) = \(param.name)
            """
            }.joined(separator: "\n")
        
        template =
        """
        \(String.required) \(acl)init\(genericTypesStr)(\(paramDeclsStr)) {
        \(paramsAssign)
            \(String.doneInit) = true
        }
        """
 
    } else {
        let callCount = "\(identifier)\(String.callCountSuffix)"
        let handlerVarName = "\(identifier)\(String.handlerSuffix)"
        let handlerVarType = handler?.type.typeName ?? "Any"
        let handlerReturn = handler?.render(with: identifier, typeKeys: typeKeys) ?? ""
        
        let suffixStr = suffix.isEmpty ? "" : "\(suffix) "
        let returnStr = returnTypeName.isEmpty ? "" : "-> \(returnTypeName)"
        let staticStr = staticKind.isEmpty ? "" : "\(staticKind) "
        let keyword = isSubscript ? "" : "func "
        let body =
        """
            \(callCount) += 1
            \(handlerReturn)
        """
            
        let wrapped = !isSubscript ? body :
        """
        
                get {
                    \(body)
                }
                set { }
        """

        template =
        """
            \(acl)\(staticStr)var \(callCount) = 0
            \(acl)\(staticStr)var \(handlerVarName): \(handlerVarType)
            \(acl)\(staticStr)\(keyword)\(name)\(genericTypesStr)(\(paramDeclsStr)) \(suffixStr)\(returnStr) {
                \(wrapped)
            }
        """
    }
    return template
}
