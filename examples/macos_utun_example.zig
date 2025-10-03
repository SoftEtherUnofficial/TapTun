//! Simple example demonstrating macOS utun device usage
//!
//! Run with: sudo zig run examples/macos_utun_example.zig
//!
//! This example:
//! 1. Opens a utun device
//! 2. Prints device information
//! 3. Shows how to read/write packets
//!
//! Note: Requires root/sudo privileges

const std = @import("std");

// Import the platform module
const macos = struct {
    pub usingnamespace @import("macos");
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== macOS utun Device Example ===\n\n", .{});

    // Open utun device (auto-allocate unit number)
    std.debug.print("Opening utun device...\n", .{});
    var device = macos.MacOSUtunDevice.open(allocator, null) catch |err| {
        std.debug.print("Error: Failed to open device: {}\n", .{err});
        std.debug.print("\nThis example requires root privileges.\n", .{});
        std.debug.print("Run with: sudo zig run examples/macos_utun_example.zig\n", .{});
        return err;
    };
    defer device.close();

    std.debug.print("✅ Device opened successfully!\n\n", .{});
    std.debug.print("Device Information:\n", .{});
    std.debug.print("  Name: {s}\n", .{device.getName()});
    std.debug.print("  Unit: {}\n", .{device.getUnit()});
    std.debug.print("  MTU:  {}\n", .{device.mtu});
    std.debug.print("  FD:   {}\n\n", .{device.fd});

    std.debug.print("Configure the interface with:\n", .{});
    std.debug.print("  sudo ifconfig {s} 10.0.0.1 10.0.0.2 netmask 255.255.255.0\n\n", .{device.getName()});

    std.debug.print("Test protocol header helpers:\n", .{});

    // Create a simple IPv4 packet
    const ipv4_packet = [_]u8{
        0x45, 0x00, 0x00, 0x28, // Version=4, IHL=5, length=40
        0x00, 0x00, 0x00, 0x00, // ID, flags, offset
        0x40, 0x01, 0x00, 0x00, // TTL=64, proto=ICMP, checksum
        0x0A, 0x00, 0x00, 0x01, // Source: 10.0.0.1
        0x0A, 0x00, 0x00, 0x02, // Dest: 10.0.0.2
    } ++ [_]u8{0} ** 20; // ICMP payload

    const with_header = try macos.addProtocolHeader(allocator, &ipv4_packet);
    defer allocator.free(with_header);

    std.debug.print("  IPv4 packet size: {} bytes\n", .{ipv4_packet.len});
    std.debug.print("  With utun header: {} bytes\n", .{with_header.len});
    std.debug.print("  Protocol family:  {} (AF_INET)\n\n", .{std.mem.readInt(u32, with_header[0..4], .big)});

    // Set non-blocking mode for the demo
    try device.setNonBlocking(true);

    std.debug.print("Device is ready for I/O!\n", .{});
    std.debug.print("\nTo test packet transmission:\n", .{});
    std.debug.print("1. Configure the interface (command above)\n", .{});
    std.debug.print("2. In another terminal: ping 10.0.0.2\n", .{});
    std.debug.print("3. This program would see the packets\n\n", .{});

    std.debug.print("Listening for packets (5 seconds)...\n", .{});
    std.debug.print("(Send traffic to see packets, or this will timeout)\n\n", .{});

    var buffer: [2048]u8 = undefined;
    var packet_count: u32 = 0;
    const start_time = std.time.milliTimestamp();

    while (std.time.milliTimestamp() - start_time < 5000) {
        const packet = device.read(&buffer) catch |err| {
            if (err == error.WouldBlock) {
                std.time.sleep(100 * std.time.ns_per_ms);
                continue;
            }
            return err;
        };

        packet_count += 1;

        // Try to strip protocol header
        const ip_packet = macos.stripProtocolHeader(packet) catch |err| {
            std.debug.print("⚠️  Packet {}: {} bytes (invalid: {})\n", .{ packet_count, packet.len, err });
            continue;
        };

        const version = (ip_packet[0] & 0xF0) >> 4;
        std.debug.print("📦 Packet {}: {} bytes, IPv{}\n", .{
            packet_count,
            ip_packet.len,
            version,
        });
    }

    if (packet_count == 0) {
        std.debug.print("No packets received (interface might not be configured)\n", .{});
    } else {
        std.debug.print("\n✅ Received {} packet(s)\n", .{packet_count});
    }

    std.debug.print("\nDevice will be closed automatically.\n", .{});
}
