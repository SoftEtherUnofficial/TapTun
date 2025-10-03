# Quick Start Guide

## 5-Minute Integration

### For SoftEtherZig Users

Replace your manual L2↔L3 translation code with ZigTapTun in just a few steps:

#### Step 1: Add Dependency (30 seconds)

```bash
cd SoftEtherZig
# Add to build.zig.zon dependencies section
```

```zig
.dependencies = .{
    .taptun = .{ .path = "../ZigTapTun" },
},
```

#### Step 2: Import in Build (30 seconds)

```zig
// build.zig
const taptun = b.dependency("taptun", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("taptun", taptun.module("taptun"));
```

#### Step 3: Replace Translation Code (3 minutes)

**Before** (packet_adapter_macos.c - ~200 lines):
```c
// Manual Ethernet header construction
UCHAR dest_mac[6];
memset(dest_mac, 0xFF, 6);  // Broadcast
UCHAR *eth_frame = Malloc(14 + ip_size);
memcpy(eth_frame, dest_mac, 6);
memcpy(eth_frame + 6, g_my_mac, 6);
eth_frame[12] = (ethertype >> 8) & 0xFF;
eth_frame[13] = ethertype & 0xFF;
memcpy(eth_frame + 14, ip_packet, ip_size);

// Manual ARP parsing
if (ethertype == 0x0806) {
    UINT16 opcode = (pkt[20] << 8) | pkt[21];
    if (opcode == 1) {
        UINT32 target_ip = (pkt[38] << 24) | ...;
        // Build ARP reply manually...
    }
}
// ... 150 more lines ...
```

**After** (with ZigTapTun - ~10 lines):
```zig
const taptun = @import("taptun");

// Initialize once
var translator = try taptun.L2L3Translator.init(allocator, .{
    .our_mac = my_mac,
    .learn_ip = true,
    .learn_gateway_mac = true,
    .handle_arp = true,
});

// Outgoing
const eth_frame = try translator.ipToEthernet(ip_packet);

// Incoming (ARP handled automatically!)
if (try translator.ethernetToIp(incoming_frame)) |ip_packet| {
    // Write to TUN
}
```

#### Step 4: Build and Test (1 minute)

```bash
zig build
sudo ./zig-out/bin/vpnclient -s server.example.com -p 443

# In another terminal:
sudo ifconfig utun8 10.21.255.100 10.21.0.1 netmask 255.255.0.0
ping 10.21.0.1  # Should work!
```

**Done!** ✅

---

## For Other Projects

### VPN Client Example

```zig
const std = @import("std");
const taptun = @import("taptun");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // 1. Generate MAC address
    var mac: [6]u8 = undefined;
    mac[0] = 0x02;  // Locally administered
    mac[1] = 0x00;
    mac[2] = 0x5E;  // SoftEther pattern
    std.crypto.random.bytes(mac[3..]);

    // 2. Initialize translator
    var translator = try taptun.L2L3Translator.init(allocator, .{
        .our_mac = mac,
        .learn_ip = true,
        .learn_gateway_mac = true,
        .handle_arp = true,
        .verbose = true,  // See what's happening
    });
    defer translator.deinit();

    // 3. Open TUN device (platform-specific, simplified here)
    const tun_fd = try openTunDevice();
    
    // 4. Configure IP
    try runCommand("ifconfig utun8 10.21.255.100 10.21.0.1 netmask 255.255.0.0");

    std.debug.print("✓ VPN ready! MAC: {X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}\n",
        .{ mac[0], mac[1], mac[2], mac[3], mac[4], mac[5] });

    // 5. Main loop
    var buf: [2048]u8 = undefined;
    while (true) {
        // Read IP packet from TUN
        const ip_packet = try readFromTun(tun_fd, &buf);
        
        // Convert to Ethernet frame
        const eth_frame = try translator.ipToEthernet(ip_packet);
        defer allocator.free(eth_frame);
        
        // Send to VPN server
        try sendToVpnServer(eth_frame);
        
        // Receive from VPN server
        if (try receiveFromVpnServer(&buf)) |incoming_frame| {
            // Convert to IP packet (or handle ARP internally)
            if (try translator.ethernetToIp(incoming_frame)) |ip_pkt| {
                defer allocator.free(ip_pkt);
                try writeToTun(tun_fd, ip_pkt);
            }
        }
    }
}
```

### Network Bridge Example

```zig
const taptun = @import("taptun");

pub fn main() !void {
    // Bridge between two interfaces with L2↔L3 translation
    
    var translator1 = try taptun.L2L3Translator.init(allocator, .{
        .our_mac = mac1,
        .learn_ip = true,
    });
    defer translator1.deinit();
    
    var translator2 = try taptun.L2L3Translator.init(allocator, .{
        .our_mac = mac2,
        .learn_ip = true,
    });
    defer translator2.deinit();
    
    // Forward packets bidirectionally with translation
    while (true) {
        // Interface 1 → Interface 2
        if (try readInterface1()) |pkt1| {
            const eth = try translator1.ipToEthernet(pkt1);
            if (try translator2.ethernetToIp(eth)) |pkt2| {
                try writeInterface2(pkt2);
            }
        }
        
        // Interface 2 → Interface 1
        if (try readInterface2()) |pkt2| {
            const eth = try translator2.ipToEthernet(pkt2);
            if (try translator1.ethernetToIp(eth)) |pkt1| {
                try writeInterface1(pkt1);
            }
        }
    }
}
```

---

## Testing

### Unit Tests

```bash
cd ZigTapTun
zig build test
```

Expected output:
```
Test [1/4] translator: basic init... OK
Test [2/4] translator: IP learning... OK
Test [3/4] arp: build request... OK
Test [4/4] arp: build reply... OK
All 4 tests passed.
```

### Manual Testing

```bash
# Terminal 1: Start VPN client
sudo ./zig-out/bin/vpnclient

# Terminal 2: Configure interface
sudo ifconfig utun8 10.21.255.100 10.21.0.1 netmask 255.255.0.0

# Terminal 3: Watch logs
tail -f /tmp/taptun.log

# Terminal 2: Test connectivity
ping -c 4 10.21.0.1
```

Look for these log messages:
```
[L2L3] Learned our IP: 10.21.255.100
[ARP] Handling request for 10.21.255.100
[ARP] Sent reply to 82:5c:48:46:b6:a2
[L2L3] Learned gateway MAC: 82:5c:48:46:b6:a2
[L2L3] L3→L2: 84 bytes IP → 98 bytes Ethernet
[L2L3] L2→L3: 98 bytes Ethernet → 84 bytes IP
```

---

## Common Issues

### Issue 1: "Permission denied" when opening TUN device

**Solution**: Run with sudo or set appropriate capabilities
```bash
sudo ./your-vpn-client
# Or on Linux:
sudo setcap cap_net_admin+ep ./your-vpn-client
```

### Issue 2: Packets sent but no replies

**Check**:
1. IP address configured? `ifconfig utun8`
2. Routing table correct? `netstat -rn`
3. Firewall blocking? `sudo pfctl -d` (macOS) or `sudo iptables -L` (Linux)
4. VPN server responding? Check server logs

**Debug**:
```zig
var translator = try taptun.L2L3Translator.init(allocator, .{
    .verbose = true,  // ← Enable verbose logging
});
```

### Issue 3: ARP not working

**Check translator configuration**:
```zig
.handle_arp = true,  // ← Must be true
.learn_ip = true,    // ← Must be true
```

**Verify IP is learned**:
```zig
if (translator.getLearnedIp()) |ip| {
    std.debug.print("Our IP: {}.{}.{}.{}\n", .{
        (ip >> 24) & 0xFF, (ip >> 16) & 0xFF,
        (ip >> 8) & 0xFF, ip & 0xFF,
    });
} else {
    std.debug.print("IP not learned yet - send a packet first!\n", .{});
}
```

---

## Performance Tips

### 1. Reuse Buffers
```zig
// Bad: Allocate every time
const eth = try translator.ipToEthernet(ip_packet);

// Good: Reuse buffer
var buf: [2048]u8 = undefined;
const eth = try translator.ipToEthernetBuf(&buf, ip_packet);
```

### 2. Batch Operations
```zig
// Process multiple packets before yielding
for (0..10) |_| {
    if (try getPacket()) |pkt| {
        try processPacket(pkt);
    } else break;
}
```

### 3. Zero-Copy Where Possible
```zig
// If your VPN library supports scatter-gather I/O:
const iovecs = [_]std.posix.iovec_const{
    .{ .base = &ethernet_header, .len = 14 },
    .{ .base = ip_packet.ptr, .len = ip_packet.len },
};
try std.posix.writev(socket_fd, &iovecs);
```

---

## Next Steps

1. **Read the full documentation**: `docs/ARCHITECTURE_DIAGRAMS.md`
2. **See more examples**: `examples/` directory
3. **Run benchmarks**: `zig build bench`
4. **Contribute**: We welcome PRs for platform support, optimizations, tests!

---

## Support

- **Issues**: https://github.com/your-org/ZigTapTun/issues
- **Discussions**: https://github.com/your-org/ZigTapTun/discussions
- **Discord**: [Join our server]

---

## License

MIT License - See LICENSE file for details.

Happy networking! 🚀
