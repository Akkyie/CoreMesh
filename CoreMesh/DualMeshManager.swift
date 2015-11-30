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

	public let ID: NSUUID
	public var delegate: MeshManagerDelegate?
	public var peers: [NSUUID] {
		let peers = self.session.connectedPeers
			.flatMap({ self.peerIDs[$0] })
		return peers
	}

	private func peerIDForMCPeerID(peerID: MCPeerID) -> NSUUID? {
		return self.peerIDs[peerID]
	}

	public required init(name: String, UUID: NSUUID) {
		self.ID = UUID
		self.peerID = MCPeerID(displayName: name)

		self.session = MCSession(
			peer: self.peerID,
			securityIdentity: nil,
			encryptionPreference: .None
		)

		self.advertizer = MCNearbyServiceAdvertiser(
			peer: self.peerID,
			discoveryInfo: ["UUID": self.ID.UUIDString],
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

		self.peerIDs[self.peerID] = self.ID
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

	public func sendData(data: NSData, to peers: [NSUUID]) throws {
		print(__FUNCTION__)
		print(self.session.connectedPeers)
		let peerIDs = self.session.connectedPeers.filter({ peerID in
			peers.contains{ self.peerIDs[peerID]?.isEqual($0) ?? false }
		})
		print(peerIDs)
		guard peerIDs.count > 0 else {
			print("No peer connected")
			return
		}
		try self.session.sendData(data, toPeers: peerIDs, withMode: .Reliable)
		print("Sent")
	}

	public func broadcastData(data: NSData) throws {
		print(__FUNCTION__)
		try self.session.sendData(data, toPeers: self.session.connectedPeers, withMode: .Reliable)
	}

	public func broadcastData(data: NSData, exceptFor peers: [NSUUID]) throws {
		print(__FUNCTION__)
		let peerIDs = self.session.connectedPeers.filter { peerID in
			!(peers.contains{ self.peerIDs[peerID]?.isEqual($0) ?? false })
		}
		try self.session.sendData(data, toPeers: peerIDs, withMode: .Reliable)
	}

}

extension DualMeshManager: MCSessionDelegate {
	public func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
		print(__FUNCTION__)

		switch state {
		case .NotConnected:
			guard let ID = self.peerIDForMCPeerID(peerID) else {
				return
			}

			self.peerIDs.removeValueForKey(peerID)

			self.delegate?.meshManager(self, peerStatusDidChange: ID, status: .NotConnected)
		case .Connecting: break;
		case .Connected:
			do {
				var dictionary = [String: AnyObject]()
				dictionary[Constants.InitTypeKey.rawValue] = Constants.InitRequestValue.rawValue
				dictionary[Constants.InitInfoKey.rawValue] = self.ID.UUIDString
				let data = try NSJSONSerialization.dataWithJSONObject(dictionary, options: [])
				try self.session.sendData(data, toPeers: [peerID], withMode: .Reliable)
			} catch {
				print(error)
			}
		}
	}

	public func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
		print(__FUNCTION__)
		print(NSString(data: data, encoding: NSUTF8StringEncoding))
		guard let ID = self.peerIDForMCPeerID(peerID) else {
			if let dictionary = try? NSJSONSerialization.JSONObjectWithData(data, options: []) {
				switch dictionary[Constants.InitTypeKey.rawValue] as? String {
				case .Some(Constants.InitRequestValue.rawValue):
					do {
						var dictionary = [String: AnyObject]()
						dictionary[Constants.InitTypeKey.rawValue] = Constants.InitResponseValue.rawValue
						dictionary[Constants.InitInfoKey.rawValue] = self.ID.UUIDString
						let data = try NSJSONSerialization.dataWithJSONObject(dictionary, options: [])
						try self.session.sendData(data, toPeers: [peerID], withMode: .Reliable)
					} catch let error as NSError {
						fatalError(error.localizedDescription)
					}
				case .Some(Constants.InitResponseValue.rawValue):
					if let
					UUIDString = dictionary[Constants.InitInfoKey.rawValue] as? String,
					UUID = NSUUID(UUIDString: UUIDString)
					{
						peerIDs[peerID] = UUID
						delegate?.meshManager(
							self,
							peerStatusDidChange: UUID,
							status: .Connected
						)
					} else {
						fatalError()
					}
				default:
					fatalError()
				}
			}
			return
		}

		self.delegate?.meshManager(self, receivedData: data, fromPeer: ID)
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
