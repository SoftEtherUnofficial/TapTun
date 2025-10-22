const std = @import("std");
const taptun = @import("taptun");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== ZigTapTun Throughput Benchmark ===\n", .{});
    std.debug.print("Platform: macOS\n", .{});
    std.debug.print("Date: 2025-10-23\n\n", .{});

    // Create translator
    var translator = try taptun.L2L3Translator.init(allocator, .{
        .our_mac = [_]u8{ 0x02, 0x00, 0x5E, 0x10, 0x20, 0x30 },
    });
    defer translator.deinit();

    const packet_sizes = [_]usize{ 64, 128, 256, 512, 1024, 1400 };
    const iterations = 10_000; // Reduced for manageable memory

    std.debug.print("Running {d} iterations per packet size...\n\n", .{iterations});

    for (packet_sizes) |size| {
        try benchEthernetToIp(&translator, allocator, size, iterations);
    }

    std.debug.print("\n=== Benchmark Complete ===\n\n", .{});
}

fn benchEthernetToIp(
    translator: *taptun.L2L3Translator,
    allocator: std.mem.Allocator,
    size: usize,
    iterations: usize,
) !void {
    // Build test packet
    const eth_packet = try allocator.alloc(u8, size);
    defer allocator.free(eth_packet);
    buildEthernetPacket(eth_packet, size);

    // Warmup
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try translator.ethernetToIp(eth_packet);
    }

    // Benchmark
    const start = std.time.nanoTimestamp();
    i = 0;
    var successful: usize = 0;
    while (i < iterations) : (i += 1) {
        if (try translator.ethernetToIp(eth_packet)) |_| {
            successful += 1;
        }
    }
    const elapsed_ns = std.time.nanoTimestamp() - start;
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;

    // Calculate metrics
    const throughput_mbps = @as(f64, @floatFromInt(successful * size * 8)) / elapsed_s / 1e6;
    const pps = @as(f64, @floatFromInt(successful)) / elapsed_s;
    const latency_us = elapsed_s * 1e6 / @as(f64, @floatFromInt(successful));

    // Report
    std.debug.print("Packet size: {d:4} bytes\n", .{size});
    std.debug.print("  Throughput: {d:10.2} Mbps\n", .{throughput_mbps});
    std.debug.print("  Packets/s:  {d:10.0}\n", .{pps});
    std.debug.print("  Latency:    {d:10.2} µs/packet\n", .{latency_us});
    std.debug.print("\n", .{});
}

fn buildEthernetPacket(buf: []u8, size: usize) void {
    // Ethernet header
    @memcpy(buf[0..6], &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }); // Dest MAC
    @memcpy(buf[6..12], &[_]u8{ 0x02, 0x00, 0x5E, 0x10, 0x20, 0x30 }); // Src MAC
    std.mem.writeInt(u16, buf[12..14][0..2], 0x0800, .big); // EtherType: IPv4

    if (size > 14) {
        // IPv4 header
        const ip_buf = buf[14..];
        const ip_size = size - 14;

        if (ip_size >= 20) {
            ip_buf[0] = 0x45; // Version 4, IHL 5
            ip_buf[1] = 0x00; // DSCP/ECN
            std.mem.writeInt(u16, ip_buf[2..4][0..2], @as(u16, @intCast(ip_size)), .big);
            std.mem.writeInt(u16, ip_buf[4..6][0..2], 0x1234, .big); // ID
            std.mem.writeInt(u16, ip_buf[6..8][0..2], 0x4000, .big); // Flags
            ip_buf[8] = 64; // TTL
            ip_buf[9] = 17; // UDP
            std.mem.writeInt(u16, ip_buf[10..12][0..2], 0x0000, .big); // Checksum
            @memcpy(ip_buf[12..16], &[_]u8{ 192, 168, 1, 10 });
            @memcpy(ip_buf[16..20], &[_]u8{ 192, 168, 1, 1 });

            if (ip_size > 20) {
                @memset(ip_buf[20..], 0x42);
            }
        }
    }
}
