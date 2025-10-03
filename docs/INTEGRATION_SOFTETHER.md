# Integration Guide: Using ZigTapTun with SoftEtherZig

This guide shows how to integrate the ZigTapTun library into SoftEtherZig to fix the L2↔L3 translation issues.

## Step 1: Add ZigTapTun as Dependency

Edit `SoftEtherZig/build.zig.zon`:

```zig
.{
    .name = "SoftEtherZig",
    .version = "0.1.0",
    .dependencies = .{
        .taptun = .{
            .path = "../ZigTapTun",  // Local path
        },
        // Or from git:
        // .taptun = .{
        //     .url = "https://github.com/your-org/ZigTapTun/archive/refs/tags/v0.1.0.tar.gz",
        //     .hash = "...",
        // },
    },
}
```

## Step 2: Update Build Configuration

Edit `SoftEtherZig/build.zig`:

```zig
const taptun = b.dependency("taptun", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("taptun", taptun.module("taptun"));
```

## Step 3: Refactor packet_adapter_macos.c

### Option A: Pure Zig Implementation (Recommended)

Create `SoftEtherZig/src/bridge/packet_adapter.zig`:

```zig
const std = @import("std");
const taptun = @import("taptun");
const c = @import("../c.zig");

pub const PacketAdapter = struct {
    device: taptun.TunDevice,
    translator: taptun.L2L3Translator,
    session: *c.SESSION,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, session: *c.SESSION) !PacketAdapter {
        // Open TUN device
        var device = try taptun.TunDevice.open(allocator, .{
            .device_type = .tun,
            .mtu = 1500,
            .enable_l2_translation = false,  // We'll handle it manually
        });
        errdefer device.close();
        
        // Generate MAC address matching SoftEther client pattern (02:00:5E:xx:xx:xx)
        var mac: [6]u8 = undefined;
        mac[0] = 0x02;
        mac[1] = 0x00;
        mac[2] = 0x5E;
        std.crypto.random.bytes(mac[3..]);
        
        // Initialize L2↔L3 translator
        var translator = try taptun.L2L3Translator.init(allocator, .{
            .our_mac = mac,
            .learn_ip = true,
            .learn_gateway_mac = true,
            .handle_arp = true,
            .verbose = true,
        });
        errdefer translator.deinit();
        
        return PacketAdapter{
            .device = device,
            .translator = translator,
            .session = session,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *PacketAdapter) void {
        self.translator.deinit();
        self.device.close();
    }
    
    /// Read packet from TUN device and convert to Ethernet frame for SoftEther
    pub fn getNextPacket(self: *PacketAdapter) !?[]const u8 {
        var buffer: [2048]u8 = undefined;
        
        // Check if ARP reply pending
        if (self.translator.arp_handler.hasPendingReply()) {
            return try self.translator.arp_handler.getPendingReply();
        }
        
        // Read IP packet from TUN device
        const ip_packet = try self.device.read(&buffer);
        if (ip_packet.len == 0) return null;
        
        // Convert IP packet to Ethernet frame (L3→L2)
        const eth_frame = try self.translator.ipToEthernet(ip_packet);
        
        return eth_frame;
    }
    
    /// Receive Ethernet frame from SoftEther and write IP packet to TUN device
    pub fn putPacket(self: *PacketAdapter, eth_frame: []const u8) !void {
        // Convert Ethernet frame to IP packet (L2→L3)
        const ip_packet_opt = try self.translator.ethernetToIp(eth_frame);
        
        if (ip_packet_opt) |ip_packet| {
            // Write IP packet to TUN device
            try self.device.write(ip_packet);
            self.allocator.free(ip_packet);
        }
        // If null, frame was handled internally (e.g., ARP)
    }
};
```

### Option B: Minimal C Wrapper (For Gradual Migration)

Create `SoftEtherZig/src/bridge/taptun_wrapper.c`:

```c
#include "../../ZigTapTun/src/taptun.h"  // C header generated from Zig

// Wrapper functions that can be called from existing C code
void* taptun_translator_init(uint8_t mac[6]) {
    // Call Zig L2L3Translator.init()
    return ...;
}

uint8_t* taptun_ip_to_ethernet(void* translator, uint8_t* ip_packet, size_t ip_len, size_t* out_len) {
    // Call translator.ipToEthernet()
    return ...;
}

uint8_t* taptun_ethernet_to_ip(void* translator, uint8_t* eth_frame, size_t eth_len, size_t* out_len) {
    // Call translator.ethernetToIp()
    return ...;
}
```

Then modify `packet_adapter_macos.c`:

```c
#include "taptun_wrapper.h"

static void* g_translator = NULL;

void MacOsTunInit(SESSION *s) {
    // ... existing code ...
    
    // Initialize translator
    g_translator = taptun_translator_init(g_my_mac);
}

UINT MacOsTunGetNextPacket(SESSION *s, void **data) {
    // ... read IP packet from TUN ...
    
    // Convert to Ethernet
    size_t eth_len;
    uint8_t* eth_frame = taptun_ip_to_ethernet(g_translator, ip_packet, ip_len, &eth_len);
    *data = eth_frame;
    return eth_len;
}

bool MacOsTunPutPacket(SESSION *s, void *data, UINT size) {
    // Convert Ethernet to IP
    size_t ip_len;
    uint8_t* ip_packet = taptun_ethernet_to_ip(g_translator, data, size, &ip_len);
    
    if (ip_packet == NULL) {
        // Packet handled internally (ARP)
        return true;
    }
    
    // Write to TUN device
    // ... existing code ...
}
```

## Step 4: Update main.zig (Pure Zig Approach)

```zig
const std = @import("std");
const taptun = @import("taptun");
const PacketAdapter = @import("bridge/packet_adapter.zig").PacketAdapter;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize VPN session (existing code)
    var session = try initVpnSession(allocator);
    defer session.deinit();
    
    // Initialize packet adapter with ZigTapTun
    var adapter = try PacketAdapter.init(allocator, session);
    defer adapter.deinit();
    
    std.debug.print("TUN device: {s}\n", .{adapter.device.getName()});
    std.debug.print("MAC address: {X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}\n",
        .{ adapter.translator.options.our_mac[0], adapter.translator.options.our_mac[1],
           adapter.translator.options.our_mac[2], adapter.translator.options.our_mac[3],
           adapter.translator.options.our_mac[4], adapter.translator.options.our_mac[5] });
    
    // Main packet forwarding loop
    while (true) {
        // Outgoing: TUN → VPN
        if (try adapter.getNextPacket()) |eth_frame| {
            defer allocator.free(eth_frame);
            try session.send(eth_frame);
        }
        
        // Incoming: VPN → TUN
        if (try session.receive()) |eth_frame| {
            defer allocator.free(eth_frame);
            try adapter.putPacket(eth_frame);
        }
    }
}
```

## Step 5: Benefits of This Approach

### Code Reusability
- ZigTapTun can be used in **any VPN project**, not just SoftEther
- Other projects: WireGuard client, OpenVPN, custom VPN solutions
- Network emulators, packet capture tools, etc.

### Cleaner Architecture
```
Before:
  SoftEtherZig → packet_adapter_macos.c (1700+ lines, L2↔L3 mixed with I/O)

After:
  SoftEtherZig → PacketAdapter (clean interface)
                 ↓
                 ZigTapTun (reusable library)
                 ├── L2L3Translator (protocol conversion)
                 ├── ArpHandler (ARP logic)
                 └── TunDevice (platform abstraction)
```

### Better Testing
```zig
test "L2↔L3 translation" {
    var translator = try L2L3Translator.init(allocator, .{ ... });
    defer translator.deinit();
    
    // Test IP → Ethernet
    const ip_packet = ...;
    const eth_frame = try translator.ipToEthernet(ip_packet);
    try testing.expectEqual(eth_frame.len, ip_packet.len + 14);
    
    // Test Ethernet → IP
    const recovered_ip = try translator.ethernetToIp(eth_frame);
    try testing.expectEqualSlices(u8, ip_packet, recovered_ip);
}
```

### Cross-Platform
Same code works on:
- macOS (utun)
- Linux (/dev/net/tun)
- Windows (TAP-Windows)
- FreeBSD (/dev/tun, /dev/tap)

## Step 6: Migration Path

### Phase 1 (Immediate): Keep C code, use ZigTapTun for translation only
- Replace manual header manipulation with ZigTapTun translator
- Keep existing TUN device I/O in C
- ~500 lines removed from packet_adapter_macos.c

### Phase 2 (Medium term): Use ZigTapTun for device I/O
- Replace macOS-specific utun code with ZigTapTun device
- Keep SoftEther protocol code in C
- Remove entire packet_adapter_macos.c

### Phase 3 (Long term): Full Zig implementation
- Rewrite SoftEther protocol in Zig
- Pure Zig VPN client
- C code only for legacy SoftEther library

## Example: Quick Test

```bash
# Build ZigTapTun
cd ZigTapTun
zig build test
zig build simple-tun

# Test with SoftEtherZig
cd ../SoftEtherZig
zig build

# Run
sudo ./zig-out/bin/vpnclient -s worxvpn.662.cloud -p 443
```

Expected output:
```
[TunDevice] Opened: utun8 (fd=8)
[L2L3] Learned our IP: 10.21.255.100
[L2L3] L3→L2: 84 bytes IP → 98 bytes Ethernet (type=0x0800)
[ARP] Handling request for 10.21.255.100
[ARP] Sent reply to 82:5c:48:46:b6:a2
[L2L3] Learned gateway MAC: 82:5c:48:46:b6:a2
[L2L3] L2→L3: 98 bytes Ethernet → 84 bytes IP
✓ Ping reply received!
```

## Conclusion

This approach gives you:
- ✅ Reusable L2↔L3 translation library
- ✅ Clean separation of concerns
- ✅ Easy testing and debugging
- ✅ Cross-platform support
- ✅ Can be used in other projects
- ✅ Gradual migration path (can keep existing C code)
