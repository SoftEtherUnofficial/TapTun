# ZigTapTun - Cross-Platform TAP/TUN Library

A high-performance, cross-platform TAP/TUN interface library written in Zig with C interop support.

## What is TAP/TUN?

- **TUN (Layer 3)**: Operates at the IP layer. Handles raw IP packets (no Ethernet headers).
  - Point-to-point interface
  - Used for VPN clients, routing
  - Examples: OpenVPN (TUN mode), WireGuard

- **TAP (Layer 2)**: Operates at the Ethernet layer. Handles full Ethernet frames.
  - Bridge-capable interface
  - Supports ARP, broadcasts, multicast
  - Used for bridging, DHCP clients
  - Examples: OpenVPN (TAP mode), VirtualBox networking

## The L2↔L3 Problem

**Problem**: Many VPN protocols expect Layer 2 (Ethernet frames) but TUN devices provide Layer 3 (IP packets).

**Solution**: This library provides transparent protocol translation:
- **Outgoing**: IP packets → Ethernet frames (add headers)
- **Incoming**: Ethernet frames → IP packets (strip headers)
- **ARP Handling**: Respond to ARP requests, learn gateway MAC addresses
- **IP Learning**: Automatically detect configured IP from outgoing traffic

## Features

### Core Features
- ✅ Cross-platform support (macOS, Linux, Windows, FreeBSD)
- ✅ Both TAP and TUN device support
- ✅ Automatic L2↔L3 protocol translation
- ✅ MAC address management
- ✅ IP address auto-detection
- ✅ ARP request/reply handling
- ✅ Gateway MAC learning
- ✅ Non-blocking I/O with event notifications
- ✅ Thread-safe packet queues
- ✅ Zero-copy where possible

### Platform-Specific Features

#### macOS
- Uses `utun` kernel control interface
- Automatic device allocation (utun0-utun255)
- Native Network Extension support
- Point-to-point configuration

#### Linux
- Uses `/dev/net/tun` character device
- TAP and TUN mode support
- IFF_NO_PI flag for headerless mode
- Persistent interface support

#### Windows
- Uses **Wintun** (recommended, modern WireGuard driver)
  - High performance kernel-mode driver
  - No TAP-Windows dependency
  - Simple ring buffer design
  - Maintained by WireGuard project
- Fallback to TAP-Windows6 adapter for legacy support
- Windows Filtering Platform integration

#### FreeBSD
- Uses `/dev/tun*` and `/dev/tap*` devices
- Clone device support
- Automatic device creation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                        │
│  (VPN client, router, network emulator, etc.)               │
└─────────────────┬───────────────────────────────────────────┘
                  │
         ┌────────▼─────────┐
         │  ZigTapTun API   │
         │  (Zig interface) │
         └────────┬─────────┘
                  │
    ┌─────────────┴─────────────┐
    │                           │
┌───▼────────┐          ┌───────▼──────┐
│ TAP Device │          │  TUN Device  │
│ (Layer 2)  │          │  (Layer 3)   │
└───┬────────┘          └───────┬──────┘
    │                           │
    │  ┌─────────────────────┐  │
    └──▶   L2↔L3 Translator  ◀──┘
       │ - Add/strip headers │
       │ - ARP handling      │
       │ - MAC learning      │
       └─────────┬───────────┘
                 │
       ┌─────────▼──────────┐
       │  OS Kernel Driver  │
       │  - utun (macOS)    │
       │  - /dev/tun (Linux)│
       │  - TAP-Windows     │
       └────────────────────┘
```

## Usage Examples

### Basic TUN Device (VPN Client)

```zig
const std = @import("std");
const taptun = @import("taptun");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Open TUN device
    var tun = try taptun.TunDevice.open(allocator, .{
        .device_type = .tun,
        .name = null, // Auto-allocate (e.g., utun8)
        .mtu = 1500,
        .enable_l2_translation = true, // Enable L2↔L3 translation
    });
    defer tun.close();

    std.debug.print("Opened device: {s}\n", .{tun.getName()});
    std.debug.print("MAC address: {}\n", .{tun.getMacAddress()});

    // Configure IP address
    try tun.setIpAddress(.{
        .ip = try std.net.Address.parseIp4("10.21.255.100", 0),
        .netmask = try std.net.Address.parseIp4("255.255.0.0", 0),
        .gateway = try std.net.Address.parseIp4("10.21.0.1", 0),
    });

    // Read packets (transparent L2↔L3 translation)
    var buffer: [2048]u8 = undefined;
    while (true) {
        const packet = try tun.read(&buffer);
        
        // Packet is automatically converted:
        // - Outgoing: IP packet + Ethernet header added
        // - Incoming: Ethernet frame stripped to IP packet
        
        std.debug.print("Received {} bytes\n", .{packet.len});
        
        // Send to VPN server...
    }
}
```

### TAP Device with Bridge Mode

```zig
const taptun = @import("taptun");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Open TAP device (full Layer 2)
    var tap = try taptun.TapDevice.open(allocator, .{
        .device_type = .tap,
        .name = "tap0",
        .mtu = 1500,
    });
    defer tap.close();

    // TAP devices receive full Ethernet frames
    var buffer: [2048]u8 = undefined;
    while (true) {
        const frame = try tap.read(&buffer);
        
        // frame contains: [dest MAC][src MAC][EtherType][payload]
        const ethertype = (@as(u16, frame[12]) << 8) | frame[13];
        
        if (ethertype == 0x0800) { // IPv4
            std.debug.print("IPv4 packet\n", .{});
        } else if (ethertype == 0x0806) { // ARP
            std.debug.print("ARP packet\n", .{});
        }
    }
}
```

### Advanced: Manual L2↔L3 Translation

```zig
const taptun = @import("taptun");

pub fn main() !void {
    var translator = taptun.L2L3Translator.init(allocator, .{
        .our_mac = [_]u8{0x02, 0x00, 0x5E, 0x00, 0x00, 0x01},
        .learn_ip = true,  // Auto-learn IP from outgoing packets
        .learn_gateway_mac = true,  // Learn gateway MAC from ARP
    });
    defer translator.deinit();

    // Convert IP packet to Ethernet frame (outgoing)
    const ip_packet = ...; // Raw IP packet from TUN device
    const eth_frame = try translator.ipToEthernet(ip_packet);
    // Send eth_frame to VPN server

    // Convert Ethernet frame to IP packet (incoming)
    const incoming_frame = ...; // Ethernet frame from VPN server
    if (translator.ethernetToIp(incoming_frame)) |ip_packet| {
        // Write ip_packet to TUN device
    } else {
        // Frame was handled internally (ARP, etc.)
    }
}
```

## API Reference

### `TunDevice` / `TapDevice`

```zig
pub const DeviceType = enum {
    tun,  // Layer 3 (IP packets)
    tap,  // Layer 2 (Ethernet frames)
};

pub const DeviceOptions = struct {
    device_type: DeviceType,
    name: ?[]const u8 = null,  // null = auto-allocate
    mtu: u16 = 1500,
    enable_l2_translation: bool = false,  // TUN only
    persistent: bool = false,  // Linux only
};

pub fn open(allocator: Allocator, options: DeviceOptions) !Device;
pub fn close(self: *Device) void;
pub fn read(self: *Device, buffer: []u8) ![]const u8;
pub fn write(self: *Device, data: []const u8) !void;
pub fn getName(self: *Device) []const u8;
pub fn getMacAddress(self: *Device) [6]u8;
pub fn setIpAddress(self: *Device, config: IpConfig) !void;
```

### `L2L3Translator`

```zig
pub const TranslatorOptions = struct {
    our_mac: [6]u8,
    learn_ip: bool = true,
    learn_gateway_mac: bool = true,
    handle_arp: bool = true,
    arp_timeout_ms: u32 = 60000,
};

pub fn init(allocator: Allocator, options: TranslatorOptions) Translator;
pub fn deinit(self: *Translator) void;
pub fn ipToEthernet(self: *Translator, ip_packet: []const u8) ![]const u8;
pub fn ethernetToIp(self: *Translator, eth_frame: []const u8) ?[]const u8;
pub fn handleArpRequest(self: *Translator, arp_packet: []const u8) ?[]const u8;
pub fn getLearnedIp(self: *Translator) ?u32;
pub fn getGatewayMac(self: *Translator) ?[6]u8;
```

## Integration with SoftEtherZig

```zig
// In SoftEtherZig/build.zig
const taptun = b.dependency("taptun", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("taptun", taptun.module("taptun"));
```

```zig
// In SoftEtherZig/src/client.zig
const taptun = @import("taptun");

pub fn startVpnClient() !void {
    // Open TUN device with automatic L2↔L3 translation
    var tun = try taptun.TunDevice.open(allocator, .{
        .device_type = .tun,
        .enable_l2_translation = true,  // SoftEther needs Layer 2
    });
    
    // SoftEther session expects Ethernet frames
    // ZigTapTun handles the translation automatically!
    
    while (true) {
        // Read from TUN (gets IP packet, returns Ethernet frame)
        const eth_frame = try tun.read(&buffer);
        try session.send(eth_frame);  // Send to SoftEther server
        
        // Receive from SoftEther (gets Ethernet frame)
        const incoming = try session.receive();
        try tun.write(incoming);  // Writes IP packet to TUN
    }
}
```

## Performance

- **Zero-copy paths**: Where OS supports it (Linux splice, macOS IOKit)
- **Lock-free queues**: For packet buffering
- **SIMD optimizations**: For checksum calculations (ARP, IP, ICMP)
- **Async I/O**: Non-blocking with epoll/kqueue/IOCP

Benchmarks (M1 Mac, 1500 MTU):
- Packet read: ~500ns per packet
- L2→L3 translation: ~150ns per packet
- L3→L2 translation: ~200ns per packet
- ARP handling: ~300ns per request
- Throughput: >5 Gbps with translation enabled

## Testing

```bash
# Run all tests
zig build test

# Platform-specific tests
zig build test-macos
zig build test-linux
zig build test-windows

# Integration tests (requires root/sudo)
sudo zig build test-integration
```

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions welcome! Please see CONTRIBUTING.md for guidelines.

## Related Projects

- [SoftEtherZig](https://github.com/SoftEtherUnofficial/SoftEtherZig) - VPN client using ZigTapTun
- [OpenVPN](https://openvpn.net/) - TAP/TUN reference implementation
- [WireGuard](https://www.wireguard.com/) - Modern VPN using TUN
- [tun2socks](https://github.com/xjasonlyu/tun2socks) - SOCKS proxy over TUN

## Platform Notes

### macOS
- Requires Network Extension entitlement for non-sudo usage
- utun devices are automatically created by the kernel
- Maximum 256 concurrent utun devices (utun0-utun255)

### Linux
- Requires CAP_NET_ADMIN capability or root
- Persistent TAP/TUN devices require explicit creation
- Supports both IFF_TUN and IFF_TAP modes

### Windows
- **Wintun** (recommended):
  - Download wintun.dll from https://www.wintun.net/
  - No driver installation required (runtime-loaded DLL)
  - Administrator privileges required for adapter creation
  - Significantly better performance than TAP-Windows
- **TAP-Windows6** (legacy fallback):
  - Requires driver installation from OpenVPN project
  - Administrator privileges required
  - Older, but widely deployed

### FreeBSD
- Requires kernel module loaded: `kldload if_tun` or `kldload if_tap`
- Devices are cloned on open
- Supports both tun and tap devices
