//
//	NetworkUtilities.swift
//	Socket
//
//	Created By Andrew Thompson on 10/12/2015.
//	Copyright (c) 2015 mrwerdo. All rights reserved.
//

import Darwin
import Foundation

public enum NetworkUtilitiesError : ErrorType {
    /// Thrown when an error occured within the Darwin module.

    /// Thrown by `gethostname()` when the system call failed. The associate
    /// value returned is from `errno`, use `strerror()` to obtain a 
    /// description.
    case GetHostNameFailed(Int32)
    /// Thrown by `sethostname()` when the system call failed. The associate
    /// value returned is from `errno`, use `strerror()` to obtain a
    /// description.
    case SetHostnameFailed(Int32)
    /// Thrown by `getaddrinfo(hostname:servname:hints:)`. The associate
    /// value is an error number returned from the system call. Use 
    /// `gai_strerror()` to access a description.
    ///
    /// **See Also**: x-man-page://ls
    case GetAddressFailed(Int32)
    /// Occurs when an invalid parameter is given.
    case ParameterError(String)
}

/// Returns the address of `obj`. 
///
/// This function is fundamentally unsafe, and
/// should be only used to get the address of a c structure. You must ensure 
/// that the object exsists throughout the whole lifetime this pointer will 
/// be used, which is typically done by ensuring the structure lives within the
/// same, or higher scope as the pointer.
private func unsafeAddressOfCObj<T: Any>(obj: UnsafeMutablePointer<T>) ->
    UnsafeMutablePointer<T> {
    return obj
}

/// Converts the bytes of `value` from network order to host order.
public func ntohs(value: CUnsignedShort) -> CUnsignedShort {
    return (value << 8) + (value >> 8)
}
/// Converts the bytes of `value` from host order to network order.
public let htons = ntohs

/// WARNING: Don't use, I don't know what it does...
public func ntohs_char(value: Int8) -> Int8 {
    return (value << 8) + (value >> 8)
}


extension String {
    /// Returns an underlying c buffer.
    /// - Warning: deallocate when done with the pointer.
    public var getCString: (ptr: UnsafeMutablePointer<Int8>, len: Int) {
        return self.withCString { (ptr: UnsafePointer<Int8>) ->
            (UnsafeMutablePointer<Int8>, Int) in
            let len = self.utf8.count
            let buffer = UnsafeMutablePointer<Int8>.alloc(len+1)
            for i in 0..<len {
                buffer[i] = ptr[i]
            }
            buffer[len] = 0
            return (buffer, len)
        }
    }
}

/// Performs the call `Darwin.getaddrinfo()`.
///
/// The `getaddrinfo(hostname:servname:hints:)` function is used to get a list 
/// of IP addresses and port numebrs for host `hostname` and service `servname`.
/// - parameter hostname: Either a valid host name or a numeric host address, 
///     consisting of a dotted decimal IPv4 address or a n IPv6 address.
/// - parameter servername: Either a decimal port number or a service name listed
///     in services(5) - see the man pages.
///
/// - Attention: `hostname` and `servername` can not be both nil, that is, only
///                 only one may be nil at a time.
/// 
/// - Throws:
///     - `NetworkUtilities.ParmeterError` when invalid parameters are present.
///     - `NetworkUtilities.LibraryError` when an error occured within 
///         `Darwin.getaddrinfo()`. The functions return value is returned as
///         an associate value, see the man pages for the corresponding error
///         codes.
public func getaddrinfo(host hostname: String?, service servername: String?,
    hints: UnsafePointer<addrinfo>) throws -> [AddrInfo] {
    
    guard !(hostname == nil && servername == nil) else {
        throw NetworkUtilitiesError.ParameterError("Host name and server name"
            + " cannot be nil at the same time!")
    }
    
    var res = addrinfo()
    var res_ptr: UnsafeMutablePointer<addrinfo> = unsafeAddressOfCObj(&res)
    let hostname_val: (ptr: UnsafeMutablePointer, len: Int) =
        hostname?.getCString ?? (nil, 0)
    let servname_val: (ptr: UnsafeMutablePointer, len: Int) =
        servername?.getCString ?? (nil, 0)
    
    defer {
        if hostname_val.len > 0 {
            hostname_val.ptr.dealloc(hostname_val.len)
        }
        if servname_val.len > 0 {
            hostname_val.ptr.dealloc(hostname_val.len)
        }
    }
    
    let error = Darwin.getaddrinfo( hostname_val.ptr,
                                    servname_val.ptr,
                                    hints, &res_ptr)
    guard error == 0 else {
        throw NetworkUtilitiesError.GetAddressFailed(error)
    }
    
    var addresses: [AddrInfo] = []
    var ptr = res_ptr
    while ptr != nil {
        addresses.append(AddrInfo(copy: ptr.memory))
        ptr = ptr.memory.ai_next
    }
    
    freeaddrinfo(res_ptr)
    return addresses
}


/// Performs the call `Darwin.gethostname()`.
///
/// The `gethostname()` function is used get the host name for the current 
/// processor.
/// - Returns: The hostname, or nil if it could not be converted to a c string.
/// - Throws: 
///     `NetworkUtilitiesError.LibraryError` when `Darwin.gethostname()` fails. 
///         `errno` is returned as an associate value, see the man pages for 
///         the meaning of the error codes.
public func gethostname() throws -> String? {
    let maxlength = Int(sysconf(_SC_HOST_NAME_MAX))
    var cstring: [Int8] = [Int8](count: maxlength, repeatedValue: 0)
    let result = Darwin.gethostname(&cstring, maxlength)
    guard result == 0 else {
        throw NetworkUtilitiesError.GetHostNameFailed(errno)
    }
    return String.fromCString(&cstring)
}
/// Performs the call `Darwin.sethostname()`.
///
/// The `sethostname(hostname:)` function is used to set the name host name for 
/// the current processor. This call is restricted to the super-user, and is
/// normally only used when the system is bootstrapped.
/// - Throws: 
///     - `NetworkUtilitiesError.ParameterError` when the length of the string
///         supplied is greater than `sysconf(_SC_HOST_NAME_MAX)`.
///     - `NetworkUtilitiesError.LibraryError` when `Darwin.sethostname()`
///         fails. `errno` is returned as an associate value, see the man pages
///         for the corresponding error.
public func sethostname(hostname: String) throws {
    let maxlength = Int(sysconf(_SC_HOST_NAME_MAX))
    let len: Int = hostname.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
    guard len <= maxlength else {
        throw NetworkUtilitiesError.ParameterError("The length of hostname" +
            " cannot be greater than sysconf(_SC_HOST_NAME_MAX)")
    }
    try hostname.withCString { (cstring: UnsafePointer<Int8>) -> Void in
        let result = Darwin.sethostname(cstring, Int32(len))
        guard result == 0 else {
            throw NetworkUtilitiesError.SetHostnameFailed(errno)
        }
    }
}

extension String {
    public static func fromCError(number: Int32) -> String {
        return String.fromCString(strerror(number))!
    }
}



// end of file