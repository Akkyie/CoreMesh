//
//  MeshManager.swift
//  CoreMesh
//
//  Created by Akio Yasui on 11/27/15.
//  Copyright © 2015 Akio Yasui. All rights reserved.
//

import Foundation

internal enum Constants: String {
	case InitTypeKey = "jp.ad.wide.sfc.CoreMesh.InitializePhase"
	case InitInfoKey = "jp.ad.wide.sfc.CoreMesh.InitializeInfo"
	case InitRequestValue = "jp.ad.wide.sfc.CoreMesh.InitializeRequest"
	case InitResponseValue = "jp.ad.wide.sfc.CoreMesh.InitializeResponse"
}

// MARK: MeshManager
public protocol MeshManager {

	var peers: [NSUUID] { get }

	init(name: String, UUID: NSUUID)

	func start()
	func stop()

	func sendData(data: NSData, to peers: [NSUUID]) throws
	func broadcastData(data: NSData) throws

}

public protocol MeshManagerDelegate {
	func meshManager(manager: MeshManager, peerStatusDidChange peerID: NSUUID, status: PeerStatus)
	func meshManager(manager: MeshManager, receivedData data: NSData, fromPeer peer: NSUUID)
}
