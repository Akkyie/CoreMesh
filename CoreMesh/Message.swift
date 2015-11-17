//
//  Message.swift
//  CoreMesh
//
//  Created by Akio Yasui on 11/27/15.
//  Copyright © 2015 Akio Yasui. All rights reserved.
//

import Foundation

infix operator <- {}

func <- <T>(inout variable: T.T, map: Map<T>) {
	switch map.mapper.type {
	case .Serialize:
		if let value = map.transformer.transform(variable) {
			map.mapper.dictionary[map.key] = value
		}
	case .Deserialize:
		if let
			v = map.mapper.dictionary[map.key],
			value = map.transformer.transform(v) {
				variable = value
		}
	}
}

func <- <T>(inout variable: T.T!, map: Map<T>) {
	switch map.mapper.type {
	case .Serialize:
		if let variable = variable, value = map.transformer.transform(variable) {
			map.mapper.dictionary[map.key] = value
		}
	case .Deserialize:
		if let
			v = map.mapper.dictionary[map.key],
			value = map.transformer.transform(v) {
				variable = value
		}
	}
}

func <- <T>(inout variable: T.T?, map: Map<T>) {
	switch map.mapper.type {
	case .Serialize:
		if let variable = variable, value = map.transformer.transform(variable) {
			map.mapper.dictionary[map.key] = value
		}
	case .Deserialize:
		if let
			v = map.mapper.dictionary[map.key],
			value = map.transformer.transform(v) {
				variable = value
		}
	}
}

struct Map<T: Transformer> {
	let mapper: Mapper
	let key: String
	let transformer: T
}

final class Mapper {

	private enum MapType {
		case Serialize
		case Deserialize
	}

	private let type: MapType
	private var dictionary: [String: String]

	init() {
		self.type = .Serialize
		self.dictionary = [:]
	}

	init(dictionary: [String: String]) {
		self.type = .Deserialize
		self.dictionary = dictionary
	}

	func map<T: Transformer>(key: String, transformer: T) -> Map<T> {
		return Map<T>(mapper: self, key: key, transformer: transformer)
	}

	func map(key: String) -> Map<StringTransformer> {
		return Map<StringTransformer>(mapper: self, key: key, transformer: StringTransformer())
	}

}

protocol Transformer {
	typealias T
	func transform(value: T) -> String?
	func transform(value: String) -> T?
}

struct StringTransformer: Transformer {
	func transform(value: String) -> String? {
		return value
	}
}

protocol IntEnumType {
	init?(rawValue: Int)
	var rawValue: Int { get }
}

struct IntEnumTransformer<U: IntEnumType>: Transformer {
	func transform(value: U) -> String? {
		return "\(value.rawValue)"
	}

	func transform(value: String) -> U? {
		return Int(value).flatMap { U(rawValue: $0) }
	}
}

struct UUIDTransformer: Transformer {
	func transform(value: NSUUID) -> String? {
		return value.UUIDString
	}

	func transform(value: String) -> NSUUID? {
		return NSUUID(UUIDString: value)
	}
}

// MARK: Message
public class Message {

	var data: NSData {
		let mapper = Mapper()
		self.map(mapper)
		guard let data = try? NSJSONSerialization.dataWithJSONObject(mapper.dictionary, options: []) else {
			fatalError()
		}
		return data
	}

	init() {

	}

	public required init?(data: NSData) {
		guard let
			object = try? NSJSONSerialization.JSONObjectWithData(data, options: []),
			dictionary = object as? [String: String]
		else {
			return nil
		}
		let mapper = Mapper(dictionary: dictionary)
		self.map(mapper)
	}

	func map(mapper: Mapper) {
		fatalError("this method have to be overrided")
	}

}

internal class RegistrationMessage: Message {

	enum RegistrationMessageType: Int, IntEnumType {
		case Request
		case Response
	}

	var type: RegistrationMessageType!
	var UUID: NSUUID!

	init(type: RegistrationMessageType, UUID: NSUUID) {
		super.init()
		self.type = type
		self.UUID = UUID
	}

	internal required init?(data: NSData) {
		super.init(data: data)
	}

	override func map(mapper: Mapper) {
		self.type <- mapper.map("type", transformer: IntEnumTransformer<RegistrationMessageType>())
		self.UUID <- mapper.map("UUID", transformer: UUIDTransformer())
	}

}
