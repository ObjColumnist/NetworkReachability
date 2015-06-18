//
//  Reachability.swift
//  NetworkReachability
//
//  Created by Spencer MacDonald on 15/06/2015.
//  Copyright (c) 2015 Square Bracket Software. All rights reserved.
//

import UIKit
import SystemConfiguration

public class Reachability {
    
    public enum Status {
        case NotReachable
        case ReachableViaWiFi
        case ReachableViaWWAN
    }
    
    public typealias StatusHandler = (Reachability, Status, Bool) -> (Void)
    
    public class func reachabilityForInternetConnection() -> Reachability {
        return Reachability(networkReachabilityRef: Reachability.networkReachabilityRefForInternetConnection(), isLocalWiFiNetworkReachabilityRef: false)
    }
    
    public class func reachabilityForLocalWiFi() -> Reachability {
        return Reachability(networkReachabilityRef: Reachability.networkReachabilityRefForLocalWiFi(), isLocalWiFiNetworkReachabilityRef: true)
    }
    
    public class func reachabilityWithHostName(hostName: String) -> Reachability {
        return Reachability(networkReachabilityRef: Reachability.networkReachabilityRefWithHostName(hostName), isLocalWiFiNetworkReachabilityRef: false)
    }
    
    private class func networkReachabilityRefForInternetConnection() -> SCNetworkReachabilityRef {
        var zeroAddress = sockaddr_in(sin_len: __uint8_t(0), sin_family: sa_family_t(0), sin_port: in_port_t(0), sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(sizeofValue(zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let networkReachabilityRef = withUnsafePointer(&zeroAddress) {
            SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, UnsafePointer($0)).takeUnretainedValue()
        }
        
        return networkReachabilityRef
    }
    
    private class func networkReachabilityRefForLocalWiFi() -> SCNetworkReachabilityRef {
        var localWifiAddress: sockaddr_in = sockaddr_in(sin_len: __uint8_t(0), sin_family: sa_family_t(0), sin_port: in_port_t(0), sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        localWifiAddress.sin_len = UInt8(sizeofValue(localWifiAddress))
        localWifiAddress.sin_family = sa_family_t(AF_INET)
        
        // IN_LINKLOCALNETNUM is defined in <netinet/in.h> as 169.254.0.0
        let address: Int64 = 0xA9FE0000
        localWifiAddress.sin_addr.s_addr = in_addr_t(address.bigEndian)
        
        let networkReachabilityRef = withUnsafePointer(&localWifiAddress) {
            SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, UnsafePointer($0)).takeUnretainedValue()
        }
        
        return networkReachabilityRef
    }
    
    private class func networkReachabilityRefWithHostName(hostName: String) -> SCNetworkReachabilityRef {
        return SCNetworkReachabilityCreateWithName(nil, hostName).takeUnretainedValue()
    }
    
    public var statusHandler: StatusHandler? {
        willSet(newValue) {
            if monitoring {
                stopMonitoring()
            }
        }
        didSet {
            if let statusHandler = statusHandler {
                startMonitoring()
            }
        }
    }
    
    public var status: Status {
        get {
            var reachabilityStatus: Status = .NotReachable
            
            var networkReachabilityFlags: SCNetworkReachabilityFlags = 0
            
            if SCNetworkReachabilityGetFlags(networkReachabilityRef, &networkReachabilityFlags) == 1 {
                if isLocalWiFiNetworkReachabilityRef {
                    reachabilityStatus = localWiFiStatusForNetworkReachabilityFlags(networkReachabilityFlags)
                }
                else {
                    reachabilityStatus = networkStatusForNetworkReachabilityFlags(networkReachabilityFlags)
                }
            }
            
            return reachabilityStatus
        }
    }
    
    public var connectionRequired: Bool {
        get {
            var networkReachabilityFlags: SCNetworkReachabilityFlags = 0
            
            if SCNetworkReachabilityGetFlags(networkReachabilityRef, &networkReachabilityFlags) == 1 {
                return (networkReachabilityFlags & SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsConnectionRequired) != 0)
            }
            
            return false
        }
    }
    
    public var reachable: Bool {
        get {
            let reachabilityStatus = status
            
            if status == .ReachableViaWiFi || status == .ReachableViaWWAN {
                return true
            }
            else {
                return false
            }
        }
    }
    
    public var reachableWithoutConnection: Bool {
        get {
            if reachable && connectionRequired == false {
                return true
            }
            else {
                return false
            }
        }
    }
    
    private var monitoring: Bool = false
    
    private let networkReachabilityRef: SCNetworkReachabilityRef
    private let isLocalWiFiNetworkReachabilityRef: Bool
    private lazy var dispatchQueue: dispatch_queue_t = dispatch_queue_create("com.squarebracketsoftware.NetworkReachability", DISPATCH_QUEUE_CONCURRENT)
    
    private init(networkReachabilityRef: SCNetworkReachabilityRef, isLocalWiFiNetworkReachabilityRef: Bool){
        self.networkReachabilityRef = networkReachabilityRef
        self.isLocalWiFiNetworkReachabilityRef = isLocalWiFiNetworkReachabilityRef
    }
    
    deinit {
        if monitoring {
            stopMonitoring()
        }
    }
    
    private func startMonitoring() -> Bool {
        var started = false
        
        if monitoring == false {
            var context = SCNetworkReachabilityContext()
            
            let block: @objc_block (SCNetworkReachabilityRef, SCNetworkReachabilityFlags, UnsafePointer<Void>) -> Void = { [weak self]
                (networkReachability: SCNetworkReachabilityRef, flags: SCNetworkReachabilityFlags, data: UnsafePointer<Void>) in
                
                if let reachability = self {
                    if let statusHandler = reachability.statusHandler {
                        statusHandler(reachability, reachability.status, reachability.connectionRequired)
                    }
                }
            }
            
            let blockObject = imp_implementationWithBlock(unsafeBitCast(block, AnyObject.self))
            let functionPointer = unsafeBitCast(blockObject, SCNetworkReachabilityCallBack.self)
            
            if SCNetworkReachabilitySetCallback(networkReachabilityRef, functionPointer, &context) == 1 {
                if SCNetworkReachabilitySetDispatchQueue(networkReachabilityRef, dispatchQueue) == 1 {
                    started = true
                }
            }
        }
        
        if started {
            monitoring = true
        }
        
        return started
    }
    
    private func stopMonitoring() -> Bool {
        var stopped = false
        
        if monitoring {
            if SCNetworkReachabilitySetCallback(networkReachabilityRef, nil, nil) == 1 {
                if SCNetworkReachabilitySetDispatchQueue(networkReachabilityRef, nil) == 1 {
                    stopped = true
                }
            }
        }
        
        if stopped {
            monitoring = false
        }
        
        return stopped
    }
    
    private func localWiFiStatusForNetworkReachabilityFlags(networkReachabilityFlags: SCNetworkReachabilityFlags) -> Status {
        
        var status: Status = .NotReachable
        
        if (networkReachabilityFlags & SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsReachable) != 0) && (networkReachabilityFlags & SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsIsDirect) != 0) {
            status = .ReachableViaWiFi
        }
        
        return status
    }
    
    private func networkStatusForNetworkReachabilityFlags(networkReachabilityFlags: SCNetworkReachabilityFlags) -> Status {
        if (networkReachabilityFlags & SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsReachable)) == 0 {
            return .NotReachable
        }
        
        var status: Status = .NotReachable
        
        if (networkReachabilityFlags & SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsConnectionRequired)) == 0 {
            status = .ReachableViaWiFi
        }
        
        if (((networkReachabilityFlags & SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsConnectionOnDemand) ) != 0) ||
            (networkReachabilityFlags & SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsConnectionOnTraffic)) != 0) {
                if (networkReachabilityFlags & SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsInterventionRequired)) == 0 {
                    status = .ReachableViaWiFi;
                }
        }
        
        if (networkReachabilityFlags & SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsIsWWAN)) == SCNetworkReachabilityFlags(kSCNetworkReachabilityFlagsIsWWAN) {
            status = .ReachableViaWWAN;
        }
        
        return status
    }
}
