# ZigTapTun iOS Integration Example

This directory contains example code for integrating ZigTapTun with iOS Network Extension (NEPacketTunnelProvider).

## Overview

iOS provides VPN functionality through the **Network Extension** framework. Unlike macOS/Linux where you have direct access to TUN devices, iOS uses a callback-based API through `NEPacketTunnelProvider`.

**Architecture:**
```
┌─────────────────────────────────────────────┐
│         iOS App (Main Target)               │
│  - Configure VPN settings                   │
│  - Start/stop tunnel                        │
│  - UI for connection status                 │
└──────────────┬──────────────────────────────┘
               │
               ├─ Shared App Group (optional)
               │
┌──────────────▼──────────────────────────────┐
│     Network Extension (Separate Process)    │
│                                             │
│  ┌─────────────────────────────────────┐  │
│  │  PacketTunnelProvider (Swift)       │  │
│  │  - NEPacketFlow callbacks           │  │
│  │  - Packet routing                   │  │
│  └──────────┬──────────────────────────┘  │
│             │ C Bridge                     │
│  ┌──────────▼──────────────────────────┐  │
│  │  ZigTapTun Native Library (Zig)     │  │
│  │  - L2L3Translator                   │  │
│  │  - Packet queues                    │  │
│  │  - Protocol conversion              │  │
│  └─────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## Files

- **`ZigTapTun-Bridging-Header.h`** - C API bridge header for Swift
- **`PacketTunnelProvider.swift`** - Example Network Extension implementation
- **`README.md`** - This file

## Requirements

### Development
- macOS with Xcode 14.0+
- Apple Developer account ($99/year for code signing)
- Zig 0.15.1+ for building native library

### Runtime
- iOS 14.0+ (target)
- iPhone or iPad (Network Extensions don't work fully in Simulator)

### Entitlements
Your app needs these entitlements:
- `com.apple.developer.networking.networkextension` (Network Extension capability)
- `com.apple.security.application-groups` (optional, for app-extension communication)

## Setup Instructions

### 1. Build ZigTapTun for iOS

```bash
cd /path/to/ZigTapTun

# Build for iOS device (ARM64)
zig build -Dtarget=aarch64-ios -Drelease=true

# Build for iOS Simulator (x86_64 or ARM64)
zig build -Dtarget=aarch64-ios-simulator -Drelease=true

# The static library will be in: zig-out/lib/libtaptun.a
```

### 2. Create Xcode Project

1. **Create iOS App:**
   - Open Xcode
   - File → New → Project
   - Choose "iOS App"
   - Name: "MyVPN" (or your app name)

2. **Add Network Extension Target:**
   - File → New → Target
   - Choose "Network Extension"
   - Choose "Packet Tunnel Provider"
   - Name: "MyVPNExtension"

### 3. Configure Network Extension Target

1. **Add ZigTapTun Library:**
   ```
   MyVPNExtension Target Settings
   ├─ Build Phases
   │  └─ Link Binary With Libraries
   │     └─ Add libtaptun.a
   ├─ Build Settings
   │  ├─ Header Search Paths
   │  │  └─ $(PROJECT_DIR)/path/to/ZigTapTun/examples/ios
   │  └─ Library Search Paths
   │     └─ $(PROJECT_DIR)/path/to/ZigTapTun/zig-out/lib
   ```

2. **Configure Bridging Header:**
   ```
   Build Settings → Swift Compiler - General
   └─ Objective-C Bridging Header
      └─ MyVPNExtension/ZigTapTun-Bridging-Header.h
   ```

3. **Copy Files:**
   - Copy `ZigTapTun-Bridging-Header.h` to your extension target
   - Copy `PacketTunnelProvider.swift` (or use as reference)

4. **Enable Entitlements:**
   ```
   MyVPNExtension.entitlements:
   
   <key>com.apple.developer.networking.networkextension</key>
   <array>
       <string>packet-tunnel-provider</string>
   </array>
   ```

### 4. Configure Main App

1. **Enable Network Extension in App:**
   ```
   MyVPN.entitlements:
   
   <key>com.apple.developer.networking.networkextension</key>
   <array>
       <string>packet-tunnel-provider</string>
   </array>
   ```

2. **Add VPN Configuration Code:**
   ```swift
   import NetworkExtension
   
   func setupVPN() {
       NETunnelProviderManager.loadAllFromPreferences { managers, error in
           var manager = managers?.first ?? NETunnelProviderManager()
           
           manager.localizedDescription = "ZigTapTun VPN"
           
           let proto = NETunnelProviderProtocol()
           proto.providerBundleIdentifier = "com.example.MyVPNExtension"
           proto.serverAddress = "VPN Server"
           manager.protocolConfiguration = proto
           
           manager.isEnabled = true
           
           manager.saveToPreferences { error in
               if error == nil {
                   print("VPN configured successfully")
               }
           }
       }
   }
   
   func startVPN() {
       NETunnelProviderManager.loadAllFromPreferences { managers, error in
           guard let manager = managers?.first else { return }
           
           do {
               try manager.connection.startVPNTunnel()
           } catch {
               print("Failed to start VPN: \(error)")
           }
       }
   }
   ```

### 5. Build and Run

1. **Build for Device:**
   - Select your device (not Simulator - Network Extensions have limited Simulator support)
   - Product → Build

2. **Install and Test:**
   - Run on device
   - Grant VPN permission when prompted
   - Start VPN from your app UI

3. **Monitor Logs:**
   ```bash
   # View Network Extension logs
   log stream --predicate 'subsystem == "com.example.zigtaptun"'
   ```

## Memory Considerations

**Network Extensions have strict memory limits:**
- Typical limit: ~50MB total memory
- Exceeding limit causes immediate termination
- Use packet pools and efficient data structures

**Tips:**
- Limit packet queue sizes (default: 256 packets each direction)
- Monitor memory usage with Instruments
- Use autorelease pool for Swift-Zig boundaries
- Avoid memory leaks (use GPA in development builds)

## Testing

### Simulator Limitations
- Network Extensions **partially work** in Simulator
- Many features require real device
- Packet capture may not work correctly

### Device Testing
1. Enable Developer Mode on device
2. Install app from Xcode
3. Grant VPN permission
4. Check Settings → VPN to see configuration
5. Use Console.app to view logs

### Packet Capture
```bash
# Capture packets on Mac (if tunneling to Mac)
sudo tcpdump -i utun7 -n -vv

# On iOS device (requires jailbreak or special provisioning)
# Use Xcode → Window → Devices and Simulators → View Device Logs
```

## Troubleshooting

### Extension Won't Start
- Check entitlements are correctly set
- Verify bridging header path is correct
- Check that libtaptun.a is linked
- Look for crash logs in Xcode Organizer

### Packets Not Flowing
- Check `zig_taptun_ios_activate()` is called
- Verify read/write loops are running
- Check packet queue sizes
- Monitor logs for errors

### Memory Crashes
- Reduce packet queue sizes
- Check for memory leaks with Instruments
- Monitor memory usage: `zig_taptun_ios_pending_write_count()`
- Use smaller MTU if needed

### Build Errors
```bash
# Rebuild ZigTapTun for correct architecture
zig build -Dtarget=aarch64-ios -Drelease=true

# Clean Xcode build folder
Product → Clean Build Folder (Shift+Cmd+K)
```

## Performance Tips

1. **Batch Packet Processing:**
   - Read multiple packets at once from NEPacketFlow
   - Write multiple packets in single call
   - Reduces context switches

2. **Efficient Timers:**
   - Use reasonable polling intervals (10-50ms)
   - Don't poll too frequently (wastes battery)
   - Consider using packet count to trigger writes

3. **Memory Pools:**
   - Pre-allocate packet buffers
   - Reuse buffers instead of allocating new ones
   - Reduces GC pressure

## Production Checklist

- [ ] Configure proper bundle IDs
- [ ] Setup app groups for app-extension communication
- [ ] Add proper error handling and recovery
- [ ] Implement connection status UI
- [ ] Add statistics/metrics collection
- [ ] Test on multiple iOS versions (14, 15, 16, 17)
- [ ] Test on different devices (iPhone, iPad)
- [ ] Profile memory usage with Instruments
- [ ] Profile battery impact
- [ ] Setup TestFlight for beta testing
- [ ] Prepare App Store submission materials

## Resources

### Apple Documentation
- [Network Extension Framework](https://developer.apple.com/documentation/networkextension)
- [NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider)
- [App Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/)

### Code Signing
- [App Distribution Guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements)

### Sample Projects
- [Apple SimpleTunnel Sample](https://developer.apple.com/library/archive/samplecode/SimpleTunnel/Introduction/Intro.html)

## Support

- **Issues:** https://github.com/SoftEtherUnofficial/ZigTapTun/issues
- **Discussions:** https://github.com/SoftEtherUnofficial/ZigTapTun/discussions
- **YouTrack:** https://youtrack.devstroop.com/project/ZTT

## License

See main project LICENSE file.
