//
//  OpenAISchemaNormalizer.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

internal enum OpenAISchemaNormalizer {
    static func normalize(
        _ schema: Any
    ) throws -> Any {
        try normalizeSchema(
            schema,
            nullable: false
        )
    }

    private static func normalizeSchema(
        _ schema: Any,
        nullable: Bool
    ) throws -> Any {
        if let object = schema as? [String: Any] {
            let normalized = try normalizeObject(object)
            return nullable ? makeNullable(normalized) : normalized
        }

        if let array = schema as? [Any] {
            return try array.map {
                try normalizeSchema(
                    $0,
                    nullable: false
                )
            }
        }

        return schema
    }

    private static func normalizeObject(
        _ schema: [String: Any]
    ) throws -> [String: Any] {
        var result = schema

        if let definitions = schema["$defs"] as? [String: Any] {
            result["$defs"] = try definitions.mapValues {
                try normalizeSchema(
                    $0,
                    nullable: false
                )
            }
        }

        for key in ["anyOf", "oneOf", "allOf"] {
            if let alternatives = schema[key] as? [Any] {
                result[key] = try alternatives.map {
                    try normalizeSchema(
                        $0,
                        nullable: false
                    )
                }
            }
        }

        if let items = schema["items"] {
            result["items"] = try normalizeSchema(
                items,
                nullable: false
            )
        }

        if let properties = schema["properties"] as? [String: Any] {
            let originallyRequired = Set(
                schema["required"] as? [String] ?? []
            )

            var normalizedProperties: [String: Any] = [:]

            for (name, propertySchema) in properties {
                normalizedProperties[name] = try normalizeSchema(
                    propertySchema,
                    nullable: !originallyRequired.contains(name)
                )
            }

            result["properties"] = normalizedProperties
            result["required"] = properties.keys.sorted()
            result["additionalProperties"] = false
        } else if isObjectSchema(schema) {
            if allowsArbitraryProperties(schema) {
                throw RemoteError.invalidRequest(
                    "OpenAI strict schemas cannot represent an object with arbitrary additional properties. Use a fixed @Generable object shape instead."
                )
            }

            result["properties"] = [String: Any]()
            result["required"] = [String]()
            result["additionalProperties"] = false
        }

        return result
    }

    private static func makeNullable(
        _ schema: [String: Any]
    ) -> [String: Any] {
        if acceptsNull(schema) {
            return schema
        }

        if let type = schema["type"] as? String {
            var result = schema
            result["type"] = [type, "null"]
            return result
        }

        if let types = schema["type"] as? [String] {
            var result = schema
            result["type"] = types + ["null"]
            return result
        }

        if let types = schema["type"] as? [Any] {
            var result = schema
            result["type"] = types + ["null"]
            return result
        }

        if let alternatives = schema["anyOf"] as? [Any] {
            var result = schema
            result["anyOf"] = alternatives + [["type": "null"]]
            return result
        }

        return [
            "anyOf": [
                schema,
                ["type": "null"]
            ]
        ]
    }

    private static func acceptsNull(
        _ schema: [String: Any]
    ) -> Bool {
        if let type = schema["type"] as? String {
            return type == "null"
        }

        if let types = schema["type"] as? [String] {
            return types.contains("null")
        }

        if let types = schema["type"] as? [Any] {
            return types.contains { ($0 as? String) == "null" }
        }

        if let alternatives = schema["anyOf"] as? [[String: Any]] {
            return alternatives.contains {
                acceptsNull($0)
            }
        }

        return false
    }

    private static func isObjectSchema(
        _ schema: [String: Any]
    ) -> Bool {
        if (schema["type"] as? String) == "object" {
            return true
        }

        if let types = schema["type"] as? [String] {
            return types.contains("object")
        }

        if let types = schema["type"] as? [Any] {
            return types.contains { ($0 as? String) == "object" }
        }

        return false
    }

    private static func allowsArbitraryProperties(
        _ schema: [String: Any]
    ) -> Bool {
        guard let additionalProperties = schema["additionalProperties"] else {
            return false
        }

        if let value = additionalProperties as? Bool {
            return value
        }

        return true
    }
}
