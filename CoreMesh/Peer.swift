//
//  Peer.swift
//  CoreMesh
//
//  Created by Akio Yasui on 11/27/15.
//  Copyright © 2015 Akio Yasui. All rights reserved.
//

import Foundation

// MARK: Peer
public func ==(lhs: Peer, rhs: Peer) -> Bool {
	return lhs.UUID == lhs.UUID
}

public typealias PeerID = NSUUID

public struct Peer: Hashable {

	public let name: String
	public let UUID: PeerID

	public var hashValue: Int {
		return UUID.hashValue
	}

}

// MARK: PeerStatus
public enum PeerStatus {
	case NotConnected
	case Connecting
	case Connected
}