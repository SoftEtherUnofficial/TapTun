# Development Quick Reference

## Quick Commands

```bash
# Build
zig build                           # Build libraries
zig build test                      # Run tests
zig build docs                      # Generate docs

# Development
zig build test --summary all        # Verbose test output
zig build -Doptimize=ReleaseFast    # Optimized build
```

## Project Structure

```
ZigTapTun/
├── src/
│   ├── taptun.zig       # Main module (exports L2L3Translator, ArpHandler)
│   ├── translator.zig   # ✅ L2↔L3 translation (COMPLETE)
│   └── arp.zig          # ✅ ARP handling (COMPLETE)
├── build.zig            # Build configuration
├── .gitignore          # Git ignore rules
├── README.md           # Full documentation
├── STATUS.md           # Current project status
└── QUICKREF.md         # This file
```

## What's Working Now

✅ **L2L3 Translation**: Convert between IP packets and Ethernet frames  
✅ **ARP Handling**: Automatic ARP request/reply processing  
✅ **IP Learning**: Auto-detect IP from outgoing traffic  
✅ **Gateway Learning**: Auto-learn gateway MAC from ARP  
✅ **Tests**: 3/3 passing  

## What's Next

🚧 Device implementations (macOS, Linux, Windows, FreeBSD)  
🚧 PacketQueue for buffering  
🚧 Integration tests  

## Using the Library Today

```zig
const taptun = @import("taptun");

var translator = try taptun.L2L3Translator.init(allocator, .{
    .our_mac = [_]u8{0x02, 0x00, 0x5E, 0x00, 0x00, 0x01},
});
defer translator.deinit();

// Outgoing: IP → Ethernet
const eth_frame = try translator.ipToEthernet(ip_packet);

// Incoming: Ethernet → IP (ARP handled automatically)
if (try translator.ethernetToIp(eth_frame)) |ip_packet| {
    // Process IP packet
}
```

## Test Results

```
✅ Build: SUCCESS (libtaptun.a + libtaptun.dylib)
✅ Tests: 3/3 PASSED
   ├─ L2L3Translator basic init
   ├─ ArpHandler basic
   └─ Core module tests
```

## Key Decisions Made

1. **Removed stubs**: Only export what's implemented
2. **Wintun for Windows**: Modern approach vs TAP-Windows
3. **Clean API**: Focus on L2↔L3 translation first
4. **Test-driven**: All functionality has tests

## Resources

- Wintun: https://www.wintun.net/
- macOS utun: `/usr/include/net/if_utun.h`
- Linux TUN: `man 4 tun`
- Project status: See STATUS.md
