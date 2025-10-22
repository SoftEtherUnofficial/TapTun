const std = @import("std");
const taptun = @import("taptun");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== ZigTapTun Latency Benchmark ===\n", .{});
    std.debug.print("Platform: macOS\n", .{});
    std.debug.print("Measuring packet processing latency...\n\n", .{});

    // Create translator
    var translator = try taptun.L2L3Translator.init(allocator, .{
        .our_mac = [_]u8{ 0x02, 0x00, 0x5E, 0x10, 0x20, 0x30 },
    });
    defer translator.deinit();

    const packet_size = 1400; // Standard MTU-sized packet
    const iterations = 10_000;

    std.debug.print("Packet size: {d} bytes\n", .{packet_size});
    std.debug.print("Iterations: {d}\n\n", .{iterations});

    // Build test packet
    const eth_packet = try allocator.alloc(u8, packet_size);
    defer allocator.free(eth_packet);
    buildEthernetPacket(eth_packet, packet_size);

    // Collect individual latency measurements
    var latencies = try allocator.alloc(u64, iterations);
    defer allocator.free(latencies);

    // Warmup
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        if (try translator.ethernetToIp(eth_packet)) |ip_slice| {
            translator.allocator.free(ip_slice);
        }
    }

    // Measure individual packet latencies
    std.debug.print("Measuring Ethernet→IP latency...\n", .{});
    i = 0;
    var valid_measurements: usize = 0;
    while (i < iterations) : (i += 1) {
        const start = std.time.nanoTimestamp();
        if (try translator.ethernetToIp(eth_packet)) |ip_slice| {
            const elapsed = std.time.nanoTimestamp() - start;
            translator.allocator.free(ip_slice);
            latencies[valid_measurements] = @as(u64, @intCast(elapsed));
            valid_measurements += 1;
        }
    }

    // Sort latencies for percentile calculation
    std.mem.sort(u64, latencies[0..valid_measurements], {}, std.sort.asc(u64));

    // Calculate percentiles
    const p50_idx = valid_measurements * 50 / 100;
    const p90_idx = valid_measurements * 90 / 100;
    const p99_idx = valid_measurements * 99 / 100;
    const p999_idx = valid_measurements * 999 / 1000;

    const p50_ns = latencies[p50_idx];
    const p90_ns = latencies[p90_idx];
    const p99_ns = latencies[p99_idx];
    const p999_ns = latencies[p999_idx];
    const min_ns = latencies[0];
    const max_ns = latencies[valid_measurements - 1];

    // Calculate mean
    var sum: u64 = 0;
    for (latencies[0..valid_measurements]) |lat| {
        sum += lat;
    }
    const mean_ns = sum / valid_measurements;

    // Report
    std.debug.print("\nLatency Statistics (Ethernet→IP):\n", .{});
    std.debug.print("  Min:     {d:8.2} µs\n", .{@as(f64, @floatFromInt(min_ns)) / 1000.0});
    std.debug.print("  Mean:    {d:8.2} µs\n", .{@as(f64, @floatFromInt(mean_ns)) / 1000.0});
    std.debug.print("  p50:     {d:8.2} µs\n", .{@as(f64, @floatFromInt(p50_ns)) / 1000.0});
    std.debug.print("  p90:     {d:8.2} µs\n", .{@as(f64, @floatFromInt(p90_ns)) / 1000.0});
    std.debug.print("  p99:     {d:8.2} µs\n", .{@as(f64, @floatFromInt(p99_ns)) / 1000.0});
    std.debug.print("  p99.9:   {d:8.2} µs\n", .{@as(f64, @floatFromInt(p999_ns)) / 1000.0});
    std.debug.print("  Max:     {d:8.2} µs\n", .{@as(f64, @floatFromInt(max_ns)) / 1000.0});

    std.debug.print("\n=== Benchmark Complete ===\n\n", .{});
}

fn buildEthernetPacket(buf: []u8, size: usize) void {
    // Ethernet header
    @memcpy(buf[0..6], &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }); // Dest MAC
    @memcpy(buf[6..12], &[_]u8{ 0x02, 0x00, 0x5E, 0x10, 0x20, 0x30 }); // Src MAC
    std.mem.writeInt(u16, buf[12..14][0..2], 0x0800, .big); // EtherType: IPv4

    if (size > 14) {
        // IPv4 header
        const ip_size = size - 14;
        const ip_buf = buf[14..];

        if (ip_size >= 20) {
            ip_buf[0] = 0x45; // Version 4, IHL 5
            ip_buf[1] = 0x00; // DSCP/ECN
            std.mem.writeInt(u16, ip_buf[2..4][0..2], @as(u16, @intCast(ip_size)), .big); // Total length
            std.mem.writeInt(u16, ip_buf[4..6][0..2], 0x1234, .big); // Identification
            std.mem.writeInt(u16, ip_buf[6..8][0..2], 0x4000, .big); // Flags
            ip_buf[8] = 64; // TTL
            ip_buf[9] = 17; // Protocol: UDP
            std.mem.writeInt(u16, ip_buf[10..12][0..2], 0x0000, .big); // Checksum
            @memcpy(ip_buf[12..16], &[_]u8{ 192, 168, 1, 10 }); // Src IP
            @memcpy(ip_buf[16..20], &[_]u8{ 192, 168, 1, 1 }); // Dst IP

            // Fill rest with dummy data
            if (ip_size > 20) {
                @memset(ip_buf[20..], 0x42);
            }
        }
    }
}
