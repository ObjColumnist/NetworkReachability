# NetworkReachability

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

`Reachability` is a class that is built upon the GCD `SCNetworkReachabilityRef` APIs, that makes it quick and easy to query and monitor the Network Reachability of your iOS or OS X device.

You can query and monitor if a remote Host Name or Address is reachable, or just that you have a Local WiFi or Internet Connection, using one of the class constructors:

```swift
public class func reachabilityForInternetConnection() -> Reachability
public class func reachabilityForLocalWiFi() -> Reachability
public class func reachabilityWithHostName(hostName: String) -> Reachability
```

Once you have initalized a Network Reachabilty object, you simply need to check the 2 properties:

```swift
public var status: Status
public var connectionRequired: Bool 
```

The `Status` enum is defined as:

```swift
public enum Status {
    case NotReachable
    case ReachableViaWiFi
    case ReachableViaWWAN
}
```

Typically you will just want to check the `reachableWithoutConnection` property (which checks the `status` and `connectionRequired` properties):

```swift
public var reachableWithoutConnection: Bool
```

If you wish to monitor reachability changes simply set the `statusHander` property, which passes in the `Reachability` as an argument:

```swift
public typealias StatusHandler = (Reachability) -> (Void)

public var statusHandler: StatusHandler?
```

## Installation

### Carthage

1. Add the following to your *Cartfile*:
  `github "ObjColumnist/NetworkReachability"`
2. Run `carthage update`
3. Add the framework as described in [Carthage Readme](https://github.com/Carthage/Carthage#adding-frameworks-to-an-application)
