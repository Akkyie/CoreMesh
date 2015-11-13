//
//  PeerListTableViewController.swift
//  CoreMeshSample
//
//  Created by Akio Yasui on 10/24/15.
//  Copyright © 2015 Akio Yasui. All rights reserved.
//

import UIKit
import CoreMesh
import GCDWebServer

enum Message: CustomStringConvertible {
	case GraphRequest(object: [String: AnyObject]?)
	case GraphResponse(object: [String: AnyObject]?)

	init?(data: NSData) {
		guard let JSONObject = try? NSJSONSerialization.JSONObjectWithData(data, options: []),
			let object = JSONObject as? [String: AnyObject],
			let key = object["key"] as? String else {
				return nil
		}
		switch key {
		case "GraphRequest":
			self = Message.GraphRequest(object: object["object"] as? [String: AnyObject])
		case "GraphResponse":
			self = Message.GraphResponse(object: object["object"] as? [String: AnyObject])
		default: return nil
		}
	}

	var key: String {
		switch self {
		case .GraphRequest: return "GraphRequest"
		case .GraphResponse: return "GraphResponse"
		}
	}

	func encode() -> NSData? {
		var data: NSData? = nil
		switch self {
		case let .GraphRequest(object: object):
			data = try? NSJSONSerialization.dataWithJSONObject(
				object == nil ? ["key": self.key] : ["key": self.key, "object": object!],
				options: []
			)
		case let .GraphResponse(object: object):
			data = try? NSJSONSerialization.dataWithJSONObject(
				object == nil ? ["key": self.key] : ["key": self.key, "object": object!],
				options: []
			)
		}
		return data
	}

	var description: String {
		guard let string = self.encode().flatMap({ NSString(data: $0, encoding: NSUTF8StringEncoding) }) as? String else {
			return "<Error: No data>"
		}
		return string
	}
}

class PeerListTableViewController: UITableViewController {

	let manager = DualMeshManager()
	var node: Node! = nil
	var graph = Graph()
	var graphs = [Peer: Graph]()
	var unitedGraph = Graph()
	var peers = [Peer]()

	let server = GCDWebServer()

	func reload() {
		self.peers = Array(self.manager.peers)
		self.tableView.reloadData()

		self.unitedGraph = self.graph
		if let data = Message.GraphRequest(object: ["name": self.manager.peer.name]).encode() {
			do {
				try self.manager.broadcastData(data)
			} catch let error {
				print(error)
			}
		}

		self.refreshControl?.endRefreshing()
	}

	override func viewDidLoad() {
		self.manager.delegate = self

		self.refreshControl = UIRefreshControl(frame: CGRectZero)
		self.refreshControl?.addTarget(self, action: "reload", forControlEvents: .ValueChanged)

		self.node = Node(id: self.manager.peer.UUID.UUIDString, label: self.manager.peer.name)
		self.graph.nodes.insert(self.node)

		NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationDidBecomeActiveNotification, object: nil, queue: nil) { _ in
			self.manager.start()
		}

		NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationWillResignActiveNotification, object: nil, queue: nil) { _ in
			self.manager.stop()
		}
	}

	override func viewWillAppear(animated: Bool) {
		guard let
			path = NSBundle.mainBundle().pathForResource("mesh", ofType: "bundle")
			else {
			return
		}

		self.server.addHandlerForMethod("GET", path: "/data.json", requestClass: GCDWebServerRequest.self) { _ in
			return GCDWebServerDataResponse(text: self.unitedGraph.JSONString(true))
		}

		self.server.addGETHandlerForBasePath("/viewer/", directoryPath: path, indexFilename: "index.html", cacheAge: 0, allowRangeRequests: true)

		self.server.startWithPort(8080, bonjourName: "")
	}

	override func viewDidAppear(animated: Bool) {
		self.manager.start()
	}

	override func viewWillDisappear(animated: Bool) {
		self.manager.stop()
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return self.peers.count
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
		cell.textLabel?.text = self.peers[indexPath.row].name
		return cell
	}

}

extension PeerListTableViewController: MeshManagerDelegate {

	func meshManager(manager: MeshManager, peerStatusDidChange peer: Peer, status: PeerStatus) {
		switch status {
		case .NotConnected:
			print("\(peer.name) is no longer connected")
			print("before: \(self.graph.nodes)")
			self.graph.nodes = Set(Array(self.graph.nodes).filter { $0.id != peer.UUID.UUIDString })
			self.graph.edges = Set(Array(self.graph.edges).filter { $0.target.id != peer.UUID.UUIDString && $0.source.id != peer.UUID.UUIDString })
			print("after: \(self.graph.edges)")
		case .Connecting:
			print("connecting to \(peer.name)…")
		case .Connected:
			print("\(peer.name) is now connected")
			let node = Node(id: peer.UUID.UUIDString, label: peer.name)
			self.graph.nodes.insert(node)
			let edge = Edge(id: NSUUID().UUIDString, source: self.node, target: node)
			self.graph.edges.insert(edge)
		}

		dispatch_async(dispatch_get_main_queue()) {
			self.peers = self.manager.peers
			self.tableView.reloadData()
		}
	}

	func meshManager(manager: MeshManager, receivedData data: NSData, fromPeer peer: Peer) {
		guard let receivedMessage = Message(data: data) else {
			fatalError()
		}

		switch receivedMessage {
		case .GraphRequest:

			guard let JSONObject = try? NSJSONSerialization.JSONObjectWithData(self.graph.JSONData(), options: []) else {
				fatalError()
			}
			let message = Message.GraphResponse(object: ["graph": JSONObject])
			guard let data = message.encode() else {
				fatalError()
			}
			do {
				try self.manager.sendData(data, peers: [peer])
			} catch {
				fatalError()
			}

		case let .GraphResponse(object: object):

			guard let
				object = object,
				graphObject = object["graph"] as? [String: AnyObject]
				else {
					fatalError()
			}

			if let nodes = (graphObject["nodes"] as? [[String: AnyObject]])?.map({ dictionary in
				return Node(id: dictionary["id"]! as! String, label: dictionary["label"]! as! String)
			}) {
				self.unitedGraph.nodes.unionInPlace(nodes)
			}

			if let edges = (graphObject["edges"] as? [[String: AnyObject]])?.map({ dictionary -> Edge in
				let source = Node(id: dictionary["source"]!["id"]! as! String, label: dictionary["source"]!["label"]! as! String)
				let target = Node(id: dictionary["target"]!["id"]! as! String, label: dictionary["target"]!["label"]! as! String)
				return Edge(id: dictionary["id"]! as! String, source: source, target: target)
			}) {
				self.unitedGraph.edges.unionInPlace(edges)
			}

			print(self.unitedGraph.JSONString(true))

		}
	}
	
}
