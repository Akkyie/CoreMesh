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

	func start()
	func stop()

	func peers() -> Set<Peer>

	func sendData(data: NSData, peers: [Peer]) throws
	func broadcastData(data: NSData) throws

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

	private func peerForID(peerID: MCPeerID) -> Peer? {
		guard let UUID = self.peerIDs[peerID] else {
			return nil
		}
		return Peer(name: peerID.displayName, UUID: UUID)
	}

	public override init() {
		self.peer = Peer(name: self.peerID.displayName, UUID: NSUUID())

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

	public func peers() -> Set<Peer> {
		return Set(self.peerIDs.map { peerID, UUID -> Peer in
			return Peer(name: peerID.displayName, UUID: UUID)
		})
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
}

extension DualMeshManager: MCSessionDelegate {
	public func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
		print(__FUNCTION__)

		guard let peer = self.peerForID(peerID) else {
			print("peer '\(peerID.displayName)' is not registered")
			return
		}

		switch state {
		case .NotConnected:
			self.peerIDs[peerID] = nil
			dispatch_async(dispatch_get_main_queue()) {
				self.delegate?.meshManager(self, peerStatusDidChange: peer, status: .NotConnected)
			}
		case .Connecting:
			dispatch_async(dispatch_get_main_queue()) {
				self.delegate?.meshManager(self, peerStatusDidChange: peer, status: .Connecting)
			}
		case .Connected:
			self.peerIDs[peerID] = peer.UUID
			dispatch_async(dispatch_get_main_queue()) {
				self.delegate?.meshManager(self, peerStatusDidChange: peer, status: .Connected)
			}
		}
	}

	public func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
		print(__FUNCTION__)
		guard let peer = self.peerForID(peerID) else {
			print("received data from unknown")
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

		guard let UUIDData = context, UUIDString = NSString(data: UUIDData, encoding: NSUTF8StringEncoding) as? String, UUID = NSUUID(UUIDString: UUIDString) else {
			invitationHandler(false, self.session)
			return
		}

		self.peerIDs[peerID] = UUID
		invitationHandler(!self.session.connectedPeers.contains(peerID), self.session)
	}

}

extension DualMeshManager: MCNearbyServiceBrowserDelegate {

	public func browser(browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
		print(__FUNCTION__)

		guard let info = info else {
			return
		}
		guard let UUIDString = info["UUID"], UUID = NSUUID(UUIDString: UUIDString) else {
			abort()
		}
		guard let UUIDData = self.peer.UUID.UUIDString.dataUsingEncoding(NSUTF8StringEncoding) else {
			abort()
		}

		self.peerIDs[peerID] = UUID
		browser.invitePeer(peerID, toSession: self.session, withContext: UUIDData, timeout: 1000)
	}

	public func browser(browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		print(__FUNCTION__)
	}

	public func browser(browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: NSError) {
		print(__FUNCTION__)
	}
	
}