//
//  CoreMesh.swift
//  CoreMesh
//
//  Created by Akio Yasui on 10/22/15.
//  Copyright © 2015 Akio Yasui. All rights reserved.
//

import UIKit

import MultipeerConnectivity

// MARK:- General Definitions
// MARK: MeshManager

public protocol MeshManager {

	var peers: [Peer] { get }

	func start()
	func stop()

	func sendData(data: NSData, peers: [Peer]) throws
	func broadcastData(data: NSData) throws

	func sendMessage(message: Message, peers: [Peer]) throws
	func broadcastMessage(message: Message) throws

}

public protocol MeshManagerDelegate {
	func meshManager(manager: MeshManager, peerStatusDidChange peer: Peer, status: PeerStatus)
	func meshManager(manager: MeshManager, receivedData data: NSData, fromPeer peer: Peer)
}

// MARK: Peer

public func ==(lhs: Peer, rhs: Peer) -> Bool {
	return lhs.UUID == lhs.UUID
}

public struct Peer: Hashable {

	public let name: String
	public let UUID: NSUUID

	public var hashValue: Int {
		return UUID.hash
	}

}

// MARK: PeerStatus

public enum PeerStatus {
	case NotConnected
	case Connecting
	case Connected
}
// MARK: Message

public protocol Message {
	var name: String { get }
	var JSON: [String: String] { get }
	var data: NSData? { get }
}

public enum Registration: Message {

	case UUIDRequest
	case UUIDResponse(UUID: NSUUID)

	public var name: String {
		switch self {
		case .UUIDRequest: return "UUIDRequest"
		case .UUIDResponse: return "UUIDResponse"
		}
	}

	public var JSON: [String: String] {
		switch self {
		case .UUIDRequest:
			return [
				"name": self.name
			]
		case let .UUIDResponse(UUID):
			return [
				"name": self.name,
				"UUID": UUID.UUIDString
			]
		}
	}

	public var data: NSData? {
		return try? NSJSONSerialization.dataWithJSONObject(self.JSON, options: [])
	}

	static func messageFromData(data: NSData) -> Registration? {
		guard let object = try? NSJSONSerialization.JSONObjectWithData(data, options: []) else {
			return nil
		}
		guard let name = object["name"] as? String else {
			return nil
		}
		if name == "UUIDRequest" {
			return Registration.UUIDRequest
		} else if let UUID = (object["UUID"] as? String).flatMap({ NSUUID(UUIDString: $0) }) where name == "UUIDResponse" {
			return Registration.UUIDResponse(UUID: UUID)
		} else {
			return nil
		}
	}

}

// MARK:- Implementation with Multipeer Connectivity

public class DualMeshManager: NSObject, MeshManager {

	private let serviceType = "CoreMesh"
	private let peerID = MCPeerID(displayName: UIDevice.currentDevice().name)

	private let session: MCSession!
	private let advertizer: MCNearbyServiceAdvertiser!
	private let browser: MCNearbyServiceBrowser!

	private var peerIDs = [MCPeerID: NSUUID]()

	public let peer: Peer
	public var delegate: MeshManagerDelegate?
	public var peers: [Peer] {
		let peers = self.session.connectedPeers
			.flatMap({ peerID in
				self.peerIDs[peerID].map({ UUID in (peerID, UUID) })
			})
			.map { Peer(name: $0.0.displayName, UUID: $0.1) }
		return peers
	}

	private func peerForID(peerID: MCPeerID) -> Peer? {
		return self.peerIDs[peerID].map({ Peer(name: peerID.displayName, UUID: $0) })
	}

	public override init() {
		self.peer = Peer(
			name: self.peerID.displayName,
			UUID: UIDevice.currentDevice().identifierForVendor ?? NSUUID()
		)

		self.session = MCSession(
			peer: self.peerID,
			securityIdentity: nil,
			encryptionPreference: .None
		)

		self.advertizer = MCNearbyServiceAdvertiser(
			peer: self.peerID,
			discoveryInfo: ["UUID": self.peer.UUID.UUIDString],
			serviceType: self.serviceType
		)

		self.browser = MCNearbyServiceBrowser(
			peer: self.peerID,
			serviceType: self.serviceType
		)

		super.init()

		self.session.delegate = self
		self.advertizer.delegate = self
		self.browser.delegate = self

		self.peerIDs[self.peerID] = self.peer.UUID
	}

	public func start() {
		print(__FUNCTION__)
		self.advertizer.startAdvertisingPeer()
		self.browser.startBrowsingForPeers()
	}

	public func stop() {
		print(__FUNCTION__)
		self.session.disconnect()
		self.advertizer.stopAdvertisingPeer()
		self.browser.stopBrowsingForPeers()
	}

	public func sendData(data: NSData, peers: [Peer]) throws {
		let peerIDs = self.session.connectedPeers.filter { peerID in
			peers.contains{ self.peerIDs[peerID]?.isEqual($0.UUID) ?? false }
		}
		try self.session.sendData(data, toPeers: peerIDs, withMode: .Reliable)
	}

	public func broadcastData(data: NSData) throws {
		try self.session.sendData(data, toPeers: self.session.connectedPeers, withMode: .Reliable)
	}

	public func broadcastData(data: NSData, exceptFor peers: [Peer]) throws {
		let peerIDs = self.session.connectedPeers.filter { peerID in
			!(peers.contains{ self.peerIDs[peerID]?.isEqual($0.UUID) ?? false })
		}
		try self.session.sendData(data, toPeers: peerIDs, withMode: .Reliable)
	}

	public func sendMessage(message: Message, peers: [Peer]) throws {
		if let data = message.data {
			try self.sendData(data, peers: peers)
		}
	}

	public func broadcastMessage(message: Message) throws {
		try self.sendMessage(message, peers: self.peers)
	}
}

extension DualMeshManager: MCSessionDelegate {
	public func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
		print(__FUNCTION__)

		switch state {
		case .NotConnected:
			guard let peer = self.peerForID(peerID) else {
				return
			}

			self.peerIDs.removeValueForKey(peerID)

			dispatch_async(dispatch_get_main_queue()) {
				self.delegate?.meshManager(self, peerStatusDidChange: peer, status: .NotConnected)
			}
		case .Connecting: break;
		case .Connected:
			guard let data = Registration.UUIDRequest.data else {
				fatalError()
			}
			do {
				try self.session.sendData(data, toPeers: [peerID], withMode: .Reliable)
			} catch {
				fatalError()
			}
		}
	}

	public func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
		print(__FUNCTION__)

		guard let peer = self.peerForID(peerID) else {
			if let message = Registration.messageFromData(data) {
				switch message {
				case .UUIDRequest:
					print("received UUIDRequest")
					guard let data = Registration.UUIDResponse(UUID: self.peer.UUID).data else {
						fatalError()
					}
					do {
						try self.session.sendData(data, toPeers: [peerID], withMode: .Reliable)
					} catch let error as NSError {
						fatalError(error.localizedDescription)
					}
				case let .UUIDResponse(UUID):
					print("received UUIDResponse")
					peerIDs[peerID] = UUID
					delegate?.meshManager(
						self,
						peerStatusDidChange: Peer(name: peerID.displayName, UUID: UUID),
						status: .Connected)
				}
			} else {
				print("received data from unknown")
			}
			return
		}

		dispatch_async(dispatch_get_main_queue()) {
			self.delegate?.meshManager(self, receivedData: data, fromPeer: peer)
		}
	}

	public func session(session: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
		print(__FUNCTION__)

	}

	public func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {
		print(__FUNCTION__)

	}

	public func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {
		print(__FUNCTION__)

	}

	public func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?, fromPeer peerID: MCPeerID, certificateHandler: (Bool) -> Void) {
		print(__FUNCTION__)
		certificateHandler(true)
	}
}

extension DualMeshManager: MCNearbyServiceAdvertiserDelegate {

	public func advertiser(advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: NSError) {
		print(__FUNCTION__)
	}

	public func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void) {
		print(__FUNCTION__)
		invitationHandler(true, self.session)
	}

}

extension DualMeshManager: MCNearbyServiceBrowserDelegate {

	public func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
		print(__FUNCTION__)
		browser.invitePeer(peerID, toSession: self.session, withContext: nil, timeout: 1000)
	}

	public func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		print(__FUNCTION__)
	}

	public func browser(browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: NSError) {
		print(__FUNCTION__)
	}
	
}