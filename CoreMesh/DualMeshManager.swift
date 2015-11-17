//
//  DualMeshManager.swift
//  CoreMesh
//
//  Created by Akio Yasui on 11/27/15.
//  Copyright © 2015 Akio Yasui. All rights reserved.
//

import Foundation

import MultipeerConnectivity

// MARK:- Implementation with Multipeer Connectivity
public final class DualMeshManager: NSObject, MeshManager {

	private let serviceType = "CoreMesh"
	private let peerID: MCPeerID

	private let session: MCSession
	private let advertizer: MCNearbyServiceAdvertiser
	private let browser: MCNearbyServiceBrowser

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

	public required init(name: String, UUID: NSUUID) {
		self.peer = Peer(
			name: name,
			UUID: UUID
		)

		self.peerID = MCPeerID(displayName: name)

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

	public func sendData(data: NSData, peers: [PeerID]) throws {
		let peerIDs = self.session.connectedPeers.filter({ peerID in
			peers.contains{ self.peerIDs[peerID]?.isEqual($0) ?? false }
		})
		try self.session.sendData(data, toPeers: peerIDs, withMode: .Reliable)
	}

	public func broadcastData(data: NSData) throws {
		try self.session.sendData(data, toPeers: self.session.connectedPeers, withMode: .Reliable)
	}

	public func broadcastData(data: NSData, exceptFor peers: [PeerID]) throws {
		let peerIDs = self.session.connectedPeers.filter { peerID in
			!(peers.contains{ self.peerIDs[peerID]?.isEqual($0) ?? false })
		}
		try self.session.sendData(data, toPeers: peerIDs, withMode: .Reliable)
	}

	public func sendMessage(message: Message, peers: [PeerID]) throws {
		try self.sendData(message.data, peers: peers)
	}

	public func broadcastMessage(message: Message) throws {
		try self.session.sendData(message.data, toPeers: self.session.connectedPeers, withMode: .Reliable)
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
			do {
				let message = RegistrationMessage(type: .Request, UUID: self.peer.UUID)
				try self.session.sendData(message.data, toPeers: [peerID], withMode: .Reliable)
			} catch {
				print(error)
			}
		}
	}

	public func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
		print(__FUNCTION__)

		guard let peer = self.peerForID(peerID) else {
			print(NSString(data: data, encoding: NSUTF8StringEncoding))
			if let message = RegistrationMessage(data: data) {
				switch message.type {
				case .Some(.Request):
					print("received UUIDRequest")
					let data = RegistrationMessage(type: .Response, UUID: self.peer.UUID).data
					do {
						try self.session.sendData(data, toPeers: [peerID], withMode: .Reliable)
					} catch let error as NSError {
						fatalError(error.localizedDescription)
					}
				case .Some(.Response):
					print("received UUIDResponse")
					peerIDs[peerID] = message.UUID
					delegate?.meshManager(
						self,
						peerStatusDidChange: Peer(name: peerID.displayName, UUID: message.UUID),
						status: .Connected)
				case .None:
					print("could not recognize message")
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
