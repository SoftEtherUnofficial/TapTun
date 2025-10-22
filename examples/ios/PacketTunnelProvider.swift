//
//  PacketTunnelProvider.swift
//  ZigTapTun iOS Network Extension Example
//
//  This demonstrates how to integrate ZigTapTun with iOS Network Extension.
//  Use this as a template for your VPN app's Network Extension target.
//

import NetworkExtension
import os.log

/// Network Extension Provider using ZigTapTun
class PacketTunnelProvider: NEPacketTunnelProvider {
    
    // Native library handle
    private var deviceHandle: ZigTapTunHandle?
    
    // Packet processing state
    private var isRunning = false
    private var readTimer: DispatchSourceTimer?
    private var writeTimer: DispatchSourceTimer?
    
    // Logging
    private let log = OSLog(subsystem: "com.example.zigtaptun", category: "PacketTunnel")
    
    // MARK: - Tunnel Lifecycle
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log("Starting ZigTapTun tunnel", log: log, type: .info)
        
        // Create native device
        guard let handle = zig_taptun_ios_create("ZigTapTun-VPN") else {
            os_log("Failed to create native device", log: log, type: .error)
            completionHandler(NEVPNError(.configurationInvalid))
            return
        }
        
        deviceHandle = handle
        
        // Configure network settings
        let settings = createNetworkSettings()
        
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                os_log("Failed to set network settings: %{public}@", 
                       log: self.log, type: .error, error.localizedDescription)
                completionHandler(error)
                return
            }
            
            // Activate native device
            zig_taptun_ios_activate(handle)
            
            // Start packet processing loops
            self.isRunning = true
            self.startReadLoop()
            self.startWriteLoop()
            
            os_log("Tunnel started successfully", log: self.log, type: .info)
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("Stopping ZigTapTun tunnel: %d", log: log, type: .info, reason.rawValue)
        
        // Stop packet processing
        isRunning = false
        readTimer?.cancel()
        writeTimer?.cancel()
        readTimer = nil
        writeTimer = nil
        
        // Deactivate and destroy native device
        if let handle = deviceHandle {
            zig_taptun_ios_deactivate(handle)
            zig_taptun_ios_destroy(handle)
            deviceHandle = nil
        }
        
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from containing app if needed
        completionHandler?(nil)
    }
    
    // MARK: - Network Configuration
    
    private func createNetworkSettings() -> NEPacketTunnelNetworkSettings {
        // Configure tunnel endpoint
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")
        
        // IPv4 settings
        let ipv4Settings = NEIPv4Settings(
            addresses: ["10.0.0.2"],
            subnetMasks: ["255.255.255.0"]
        )
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4Settings
        
        // MTU
        settings.mtu = 1500
        
        // DNS (optional)
        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        settings.dnsSettings = dnsSettings
        
        // Configure native device with same settings
        if let handle = deviceHandle {
            // Convert IP string to uint32 (network byte order)
            let address = ipStringToUInt32("10.0.0.2")
            let netmask = ipStringToUInt32("255.255.255.0")
            _ = zig_taptun_ios_set_ipv4(handle, address, netmask)
            _ = zig_taptun_ios_set_mtu(handle, 1500)
        }
        
        return settings
    }
    
    // MARK: - Packet Processing
    
    /// Start loop to read packets from NEPacketFlow and send to native device
    private func startReadLoop() {
        guard isRunning else { return }
        
        // Read packets from system
        packetFlow.readPackets { [weak self] (packets: [Data], protocols: [NSNumber]) in
            guard let self = self, self.isRunning else { return }
            
            // Enqueue each packet to native device
            for packet in packets {
                packet.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    guard let baseAddress = bytes.baseAddress else { return }
                    
                    let result = zig_taptun_ios_enqueue_read(
                        self.deviceHandle!,
                        baseAddress.assumingMemoryBound(to: UInt8.self),
                        bytes.count
                    )
                    
                    if result != ZigTapTunError_Success {
                        os_log("Failed to enqueue packet: %d", 
                               log: self.log, type: .error, result.rawValue)
                    }
                }
            }
            
            // Continue reading
            self.startReadLoop()
        }
    }
    
    /// Start loop to dequeue packets from native device and send via NEPacketFlow
    private func startWriteLoop() {
        let queue = DispatchQueue(label: "com.example.zigtaptun.write", qos: .userInitiated)
        
        writeTimer = DispatchSource.makeTimerSource(queue: queue)
        writeTimer?.schedule(deadline: .now(), repeating: .milliseconds(10))
        
        writeTimer?.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            
            self.processOutgoingPackets()
        }
        
        writeTimer?.resume()
    }
    
    /// Dequeue and send packets from native device
    private func processOutgoingPackets() {
        guard let handle = deviceHandle else { return }
        
        let maxPacketSize = 2048
        var buffer = [UInt8](repeating: 0, count: maxPacketSize)
        var packets: [Data] = []
        var protocols: [NSNumber] = []
        
        // Dequeue up to 32 packets at a time
        for _ in 0..<32 {
            var length: size_t = 0
            
            let result = buffer.withUnsafeMutableBufferPointer { bufferPtr in
                zig_taptun_ios_dequeue_write(
                    handle,
                    bufferPtr.baseAddress!,
                    maxPacketSize,
                    &length
                )
            }
            
            if result == ZigTapTunError_WouldBlock {
                break // No more packets
            }
            
            if result != ZigTapTunError_Success {
                os_log("Failed to dequeue packet: %d", 
                       log: log, type: .error, result.rawValue)
                break
            }
            
            if length > 0 {
                let packet = Data(buffer[0..<length])
                packets.append(packet)
                
                // Determine protocol from IP version
                let version = buffer[0] >> 4
                let proto: NSNumber = (version == 4) ? AF_INET as NSNumber : AF_INET6 as NSNumber
                protocols.append(proto)
            }
        }
        
        // Send packets if we have any
        if !packets.isEmpty {
            packetFlow.writePackets(packets, withProtocols: protocols)
        }
    }
    
    // MARK: - Utilities
    
    private func ipStringToUInt32(_ ipString: String) -> UInt32 {
        var addr = in_addr()
        inet_pton(AF_INET, ipString, &addr)
        return addr.s_addr
    }
}

// MARK: - Example Integration in VPN App

/*
 
 To use this in your iOS VPN app:
 
 1. Create Network Extension target in Xcode:
    - File > New > Target > Network Extension
    - Choose "Packet Tunnel"
    
 2. Add ZigTapTun library:
    - Build ZigTapTun as static library for iOS
    - Add to Network Extension target
    - Configure bridging header
    
 3. Configure entitlements:
    - com.apple.developer.networking.networkextension
    - com.apple.security.application-groups (for app communication)
    
 4. Build ZigTapTun for iOS:
    ```bash
    zig build -Dtarget=aarch64-ios -Doptimize=ReleaseFast
    ```
    
 5. In your main app, start VPN:
    ```swift
    let manager = NETunnelProviderManager()
    manager.loadFromPreferences { error in
        if error == nil {
            try? manager.connection.startVPNTunnel()
        }
    }
    ```
 
 See Apple's Network Extension documentation for full details:
 https://developer.apple.com/documentation/networkextension
 
 */
