//
//  Graph.swift
//  CoreMesh
//
//  Created by Akio Yasui on 10/24/15.
//  Copyright © 2015 Akio Yasui. All rights reserved.
//

import Foundation
import Darwin

func ==(lhs: Graph, rhs: Graph) -> Bool {
	return lhs.nodes == rhs.nodes && lhs.edges == rhs.edges
}

func ==(lhs: Node, rhs: Node) -> Bool {
	return lhs.id == rhs.id
}

func ==(lhs: Edge, rhs: Edge) -> Bool {
	return lhs.source.id == rhs.source.id && lhs.target.id == rhs.target.id
}

struct Graph: Equatable {
	var nodes = Set<Node>()
	var edges = Set<Edge>()

	init() {
		
	}
}

struct Node: Equatable, Hashable, CustomStringConvertible {
	let id: String
	let label: String

	var hashValue: Int {
		return self.id.hashValue
	}

	var description: String {
		return label
	}

	var debugDescription: String {
		return label
	}

	init(id: String, label: String) {
		self.id = id
		self.label = label
	}
}

struct Edge: Equatable, Hashable, CustomStringConvertible {
	let id: String
	let source: Node
	let target: Node

	var hashValue: Int {
		return self.id.hashValue
	}

	var description: String {
		return "\(source) <-> \(target)"
	}

	init(id: String, source: Node, target: Node) {
		self.id = id
		self.source = source
		self.target = target
	}
}

extension Graph {
	func JSONString(sigma: Bool = false) -> String {
		let nodesJSON = "[\(nodes.map({ $0.JSONString(sigma) }).joinWithSeparator(", "))]"
		let edgesJSON = "[\(edges.map({ $0.JSONString(sigma) }).joinWithSeparator(", "))]"
		return "{ \"nodes\": \(nodesJSON), \"edges\": \(edgesJSON) }"
	}

	func JSONData(sigma: Bool = false) -> NSData {
		return self.JSONString(sigma).dataUsingEncoding(NSUTF8StringEncoding)!
	}
}

extension Node {
	func JSONString(sigma: Bool = false) -> String {
		let x = Double(arc4random_uniform(UInt32.max)) / Double(UInt32.max) / 2.0
		let y = Double(arc4random_uniform(UInt32.max)) / Double(UInt32.max) / 2.0
		return sigma
			? "{ \"id\": \"\(id)\", \"label\": \"\(label)\", \"size\": 1, \"x\": \(x), \"y\": \(y) }"
			: "{ \"id\": \"\(id)\", \"label\": \"\(label)\" }"
	}
}

extension Edge {
	func JSONString(sigma: Bool = false) -> String {
		return sigma
			? "{ \"id\": \"\(id)\", \"source\": \"\(source.id)\", \"target\": \"\(target.id)\" }"
			: "{ \"id\": \"\(id)\", \"source\": \(source.JSONString(sigma)), \"target\": \(target.JSONString(sigma)) }"
	}
}
