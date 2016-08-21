//
//  Reachability.swift
//  NetworkReachability
//
//  Created by Spencer MacDonald on 15/06/2015.
//  Copyright (c) 2015 Square Bracket Software. All rights reserved.
//

import Foundation
import SystemConfiguration

public final class Reachability {
    public enum Status {
        case notReachable
        case reachableViaWiFi
        case reachableViaWWAN
    }
    
    public typealias StatusHandler = (Reachability) -> (Void)
    
    public class func forInternetConnection() -> Reachability {
        return Reachability(networkReachabilityRef: Reachability.networkReachabilityRefForInternetConnection(), isLocalWiFiNetworkReachabilityRef: false)
    }
    
    public class func forLocalWiFi() -> Reachability {
        return Reachability(networkReachabilityRef: Reachability.networkReachabilityRefForLocalWiFi(), isLocalWiFiNetworkReachabilityRef: true)
    }
    
    public class func with(_ name: String) -> Reachability {
        return Reachability(networkReachabilityRef: Reachability.networkReachabilityRefWithName(name), isLocalWiFiNetworkReachabilityRef: false)
    }
    
    fileprivate class func networkReachabilityRefForInternetConnection() -> SCNetworkReachability {
        var zeroAddress = sockaddr_in(sin_len: __uint8_t(0), sin_family: sa_family_t(0), sin_port: in_port_t(0), sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let networkReachabilityRef = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        return networkReachabilityRef!
    }
    
    fileprivate class func networkReachabilityRefForLocalWiFi() -> SCNetworkReachability {
        var localWifiAddress: sockaddr_in = sockaddr_in(sin_len: __uint8_t(0), sin_family: sa_family_t(0), sin_port: in_port_t(0), sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        localWifiAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localWifiAddress.sin_family = sa_family_t(AF_INET)
        
        // IN_LINKLOCALNETNUM is defined in <netinet/in.h> as 169.254.0.0
        let address: Int64 = 0xA9FE0000
        localWifiAddress.sin_addr.s_addr = in_addr_t(address.bigEndian)
        
        let networkReachabilityRef = withUnsafePointer(to: &localWifiAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        return networkReachabilityRef!
    }
    
    fileprivate class func networkReachabilityRefWithName(_ name: String) -> SCNetworkReachability {
        return SCNetworkReachabilityCreateWithName(nil, name)!
    }
    
    public var statusHandler: StatusHandler? {
        willSet(newValue) {
            if isMonitoring {
                _ = stopMonitoring()
            }
        }
        didSet {
            if let _ = statusHandler {
                _ = startMonitoring()
            }
        }
    }
    
    public var status: Status {
        var reachabilityStatus: Status = .notReachable
        
        var networkReachabilityFlags: SCNetworkReachabilityFlags = []
        
        if SCNetworkReachabilityGetFlags(networkReachabilityRef, &networkReachabilityFlags) == true {
            if isLocalWiFiNetworkReachabilityRef {
                reachabilityStatus = localWiFiStatus(for: networkReachabilityFlags)
            } else {
                reachabilityStatus = networkStatus(for: networkReachabilityFlags)
            }
        }
        
        return reachabilityStatus
    }
    
    public var isConnectionRequired: Bool {
        var networkReachabilityFlags: SCNetworkReachabilityFlags = []
        
        if SCNetworkReachabilityGetFlags(networkReachabilityRef, &networkReachabilityFlags) == true {
            return (networkReachabilityFlags.rawValue & SCNetworkReachabilityFlags.connectionRequired.rawValue != 0)
        }
        
        return false
    }
    
    public var isReachable: Bool {
        if status == .reachableViaWiFi || status == .reachableViaWWAN {
            return true
        } else {
            return false
        }
    }
    
    public var isReachableWithoutConnection: Bool {
        if isReachable && isConnectionRequired == false {
            return true
        } else {
            return false
        }
    }
    
    fileprivate var isMonitoring: Bool = false
    
    fileprivate let networkReachabilityRef: SCNetworkReachability
    fileprivate let isLocalWiFiNetworkReachabilityRef: Bool
    fileprivate lazy var dispatchQueue: DispatchQueue = DispatchQueue(label: "com.squarebracketsoftware.NetworkReachability", attributes: DispatchQueue.Attributes.concurrent)
    
    fileprivate init(networkReachabilityRef: SCNetworkReachability, isLocalWiFiNetworkReachabilityRef: Bool) {
        self.networkReachabilityRef = networkReachabilityRef
        self.isLocalWiFiNetworkReachabilityRef = isLocalWiFiNetworkReachabilityRef
    }
    
    deinit {
        if isMonitoring {
            _ = stopMonitoring()
        }
    }
    
    fileprivate func startMonitoring() -> Bool {
        var started = false
        
        if isMonitoring == false {
            var context = SCNetworkReachabilityContext()
            
            let block: @convention(block) (SCNetworkReachability, SCNetworkReachabilityFlags, UnsafeRawPointer) -> Void = { [weak self]
                (networkReachability: SCNetworkReachability, flags: SCNetworkReachabilityFlags, data: UnsafeRawPointer) in
                
                if let reachability = self {
                    if let statusHandler = reachability.statusHandler {
                        statusHandler(reachability)
                    }
                }
            }
            
            let blockObject = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
            let functionPointer = unsafeBitCast(blockObject, to: SCNetworkReachabilityCallBack.self)
            
            if SCNetworkReachabilitySetCallback(networkReachabilityRef, functionPointer, &context) == true {
                if SCNetworkReachabilitySetDispatchQueue(networkReachabilityRef, dispatchQueue) == true {
                    started = true
                }
            }
        }
        
        if started {
            isMonitoring = true
        }
        
        return started
    }
    
    fileprivate func stopMonitoring() -> Bool {
        var stopped = false
        
        if isMonitoring {
            if SCNetworkReachabilitySetCallback(networkReachabilityRef, nil, nil) == true {
                if SCNetworkReachabilitySetDispatchQueue(networkReachabilityRef, nil) == true {
                    stopped = true
                }
            }
        }
        
        if stopped {
            isMonitoring = false
        }
        
        return stopped
    }
    
    fileprivate func localWiFiStatus(for networkReachabilityFlags: SCNetworkReachabilityFlags) -> Status {
        var status: Status = .notReachable
        
        if (networkReachabilityFlags.rawValue & SCNetworkReachabilityFlags.reachable.rawValue != 0) && (networkReachabilityFlags.rawValue & SCNetworkReachabilityFlags.isDirect.rawValue != 0) {
            status = .reachableViaWiFi
        }
        
        return status
    }
    
    fileprivate func networkStatus(for networkReachabilityFlags: SCNetworkReachabilityFlags) -> Status {
        if (networkReachabilityFlags.rawValue & SCNetworkReachabilityFlags.reachable.rawValue) == 0 {
            return .notReachable
        }
        
        var status: Status = .notReachable
        
        if (networkReachabilityFlags.rawValue & SCNetworkReachabilityFlags.connectionRequired.rawValue) == 0 {
            status = .reachableViaWiFi
        }
        
        if (((networkReachabilityFlags.rawValue & SCNetworkReachabilityFlags.connectionOnDemand.rawValue ) != 0) ||
            (networkReachabilityFlags.rawValue & SCNetworkReachabilityFlags.connectionOnTraffic.rawValue) != 0) {
                if (networkReachabilityFlags.rawValue & SCNetworkReachabilityFlags.interventionRequired.rawValue) == 0 {
                    status = .reachableViaWiFi
                }
        }
        
        if (networkReachabilityFlags.rawValue & SCNetworkReachabilityFlags.isWWAN.rawValue) == SCNetworkReachabilityFlags.isWWAN.rawValue {
            status = .reachableViaWWAN
        }
        
        return status
    }
}
