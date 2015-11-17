//
//  MeshManager.swift
//  CoreMesh
//
//  Created by Akio Yasui on 11/27/15.
//  Copyright © 2015 Akio Yasui. All rights reserved.
//

import Foundation

// MARK: MeshManager
public protocol MeshManager {

	var peers: [Peer] { get }

	init(name: String, UUID: NSUUID)

	func start()
	func stop()

	func sendData(data: NSData, peers: [PeerID]) throws
	func broadcastData(data: NSData) throws

	func sendMessage(message: Message, peers: [PeerID]) throws
	func broadcastMessage(message: Message) throws

}

public protocol MeshManagerDelegate {
	func meshManager(manager: MeshManager, peerStatusDidChange peer: Peer, status: PeerStatus)
	func meshManager(manager: MeshManager, receivedData data: NSData, fromPeer peer: Peer)
}
