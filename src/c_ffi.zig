//! C FFI for TapTun L2↔L3 Translator
//! Provides simple C API for use in iOS/Android packet adapters

const std = @import("std");
const taptun = @import("taptun.zig");

// Global allocator for C FFI (uses libc malloc/free)
var gpa = std.heap.c_allocator;

/// Opaque handle to L2L3Translator
pub const TapTunTranslator = opaque {};

/// Create a new L2L3 translator
/// @param our_mac: 6-byte MAC address
/// @return Opaque translator handle, or NULL on failure
pub export fn taptun_translator_create(our_mac: [*]const u8) ?*TapTunTranslator {
    const mac: [6]u8 = our_mac[0..6].*;

    const translator = gpa.create(taptun.L2L3Translator) catch return null;
    translator.* = taptun.L2L3Translator.init(gpa, .{
        .our_mac = mac,
        .learn_ip = true,
        .learn_gateway_mac = true,
        .handle_arp = true, // MUST handle ARP - Android/iOS cannot process L2 protocols!
        .verbose = false, // Disable verbose logging for performance
    }) catch {
        gpa.destroy(translator);
        return null;
    };

    return @ptrCast(translator);
}

/// Destroy translator and free resources
pub export fn taptun_translator_destroy(handle: ?*TapTunTranslator) void {
    if (handle) |h| {
        const translator: *taptun.L2L3Translator = @ptrCast(@alignCast(h));
        translator.deinit();
        gpa.destroy(translator);
    }
}

/// Convert Ethernet frame (L2) to IP packet (L3)
/// @param handle: Translator handle
/// @param eth_frame: Ethernet frame buffer
/// @param frame_len: Length of Ethernet frame
/// @param out_ip_packet: Output buffer for IP packet
/// @param out_buffer_size: Size of output buffer
/// @return Length of IP packet (>0), 0 if handled internally (ARP), or -1 on error
pub export fn taptun_ethernet_to_ip(
    handle: ?*TapTunTranslator,
    eth_frame: [*]const u8,
    frame_len: usize,
    out_ip_packet: [*]u8,
    out_buffer_size: usize,
) c_int {
    const translator: *taptun.L2L3Translator = @ptrCast(@alignCast(handle orelse {
        std.debug.print("[TapTun C FFI] ERROR: ethernet_to_ip called with NULL handle\n", .{});
        return -1;
    }));

    if (frame_len == 0) {
        std.debug.print("[TapTun C FFI] ERROR: ethernet_to_ip called with zero length\n", .{});
        return -1;
    }

    const frame = eth_frame[0..frame_len];

    // Convert Ethernet to IP (may return null if ARP handled internally)
    const ip_packet = translator.ethernetToIp(frame) catch |err| {
        std.debug.print("[TapTun C FFI] ERROR: ethernetToIp failed with error: {any}\n", .{err});
        return -1;
    };

    if (ip_packet) |pkt| {
        defer gpa.free(pkt); // Free allocated IP packet

        if (pkt.len > out_buffer_size) {
            std.debug.print("[TapTun C FFI] ERROR: IP packet too large: {d} > {d}\n", .{ pkt.len, out_buffer_size });
            return -2; // Buffer too small
        }

        @memcpy(out_ip_packet[0..pkt.len], pkt);

        // Log successful conversion (first few only)
        const count = translator.packets_translated_l2_to_l3;
        if (count <= 5) {
            std.debug.print("[TapTun C FFI] ✅ ethernet_to_ip #{d}: {d} bytes Ethernet → {d} bytes IP\n", .{ count, frame_len, pkt.len });
        }

        return @intCast(pkt.len);
    }

    // ARP handled, no IP packet to return
    const arp_count = translator.arp_requests_handled;
    if (arp_count <= 5) {
        std.debug.print("[TapTun C FFI] 🔧 ethernet_to_ip: ARP handled #{d}\n", .{arp_count});
    }

    return 0; // ARP handled, no IP packet to return
}

/// Convert IP packet (L3) to Ethernet frame (L2)
/// @param handle: Translator handle
/// @param ip_packet: IP packet buffer
/// @param packet_len: Length of IP packet
/// @param out_eth_frame: Output buffer for Ethernet frame
/// @param out_buffer_size: Size of output buffer
/// @return Length of Ethernet frame, or -1 on error
pub export fn taptun_ip_to_ethernet(
    handle: ?*TapTunTranslator,
    ip_packet: [*]const u8,
    packet_len: usize,
    out_eth_frame: [*]u8,
    out_buffer_size: usize,
) c_int {
    const translator: *taptun.L2L3Translator = @ptrCast(@alignCast(handle orelse {
        std.debug.print("[TapTun C FFI] ERROR: ip_to_ethernet called with NULL handle\n", .{});
        return -1;
    }));

    if (packet_len == 0) {
        std.debug.print("[TapTun C FFI] ERROR: ip_to_ethernet called with zero length\n", .{});
        return -1;
    }

    if (packet_len > out_buffer_size) {
        std.debug.print("[TapTun C FFI] ERROR: ip_to_ethernet packet too large: {d} > {d}\n", .{ packet_len, out_buffer_size });
        return -2;
    }

    const packet = ip_packet[0..packet_len];

    // Convert IP to Ethernet
    const eth_frame = translator.ipToEthernet(packet) catch |err| {
        std.debug.print("[TapTun C FFI] ERROR: ipToEthernet failed with error: {any}\n", .{err});
        return -1;
    };
    defer gpa.free(eth_frame); // Free allocated Ethernet frame

    if (eth_frame.len > out_buffer_size) {
        std.debug.print("[TapTun C FFI] ERROR: Ethernet frame too large: {d} > {d}\n", .{ eth_frame.len, out_buffer_size });
        gpa.free(eth_frame);
        return -2; // Buffer too small
    }

    @memcpy(out_eth_frame[0..eth_frame.len], eth_frame);

    // Log successful conversion (first few only)
    const count = translator.packets_translated_l3_to_l2;
    if (count <= 5) {
        std.debug.print("[TapTun C FFI] ✅ ip_to_ethernet #{d}: {d} bytes IP → {d} bytes Ethernet\n", .{ count, packet_len, eth_frame.len });
    }

    return @intCast(eth_frame.len);
}

/// Get translator statistics
pub export fn taptun_translator_stats(
    handle: ?*TapTunTranslator,
    out_l2_to_l3: ?*u64,
    out_l3_to_l2: ?*u64,
    out_arp_handled: ?*u64,
) void {
    const translator: *taptun.L2L3Translator = @ptrCast(@alignCast(handle orelse return));

    if (out_l2_to_l3) |ptr| ptr.* = translator.packets_translated_l2_to_l3;
    if (out_l3_to_l2) |ptr| ptr.* = translator.packets_translated_l3_to_l2;
    if (out_arp_handled) |ptr| ptr.* = translator.arp_requests_handled;
}

/// Check if gateway MAC has been learned
/// @return 1 if learned, 0 if not
pub export fn taptun_translator_has_gateway_mac(handle: ?*TapTunTranslator) c_int {
    const translator: *taptun.L2L3Translator = @ptrCast(@alignCast(handle orelse return 0));
    return if (translator.gateway_mac != null) 1 else 0;
}

/// Get learned gateway MAC address
/// @param out_mac: 6-byte buffer to receive MAC address
/// @return 1 if MAC was learned, 0 if not
pub export fn taptun_translator_get_gateway_mac(
    handle: ?*TapTunTranslator,
    out_mac: [*]u8,
) c_int {
    const translator: *taptun.L2L3Translator = @ptrCast(@alignCast(handle orelse return 0));

    if (translator.gateway_mac) |mac| {
        @memcpy(out_mac[0..6], &mac);
        return 1;
    }

    return 0;
}

/// Check if there are pending ARP replies to send
/// @param handle: Translator handle
/// @return 1 if ARP replies available, 0 if not
pub export fn taptun_translator_has_arp_reply(handle: ?*TapTunTranslator) c_int {
    const translator: *taptun.L2L3Translator = @ptrCast(@alignCast(handle orelse return 0));
    return if (translator.hasPendingArpReply()) 1 else 0;
}

/// Get next queued ARP reply (Ethernet frame)
/// @param handle: Translator handle
/// @param out_frame: Output buffer for Ethernet frame
/// @param out_buffer_size: Size of output buffer
/// @return Length of Ethernet frame (typically 42-60 bytes), 0 if no replies, -1 on error, -2 if buffer too small
pub export fn taptun_translator_pop_arp_reply(
    handle: ?*TapTunTranslator,
    out_frame: [*]u8,
    out_buffer_size: usize,
) c_int {
    const translator: *taptun.L2L3Translator = @ptrCast(@alignCast(handle orelse {
        std.debug.print("[TapTun C FFI] ERROR: pop_arp_reply called with NULL handle\n", .{});
        return -1;
    }));

    // Check if there are any replies
    if (!translator.hasPendingArpReply()) {
        return 0; // No replies available
    }

    // Pop the next ARP reply
    const arp_frame = translator.popArpReply() orelse {
        std.debug.print("[TapTun C FFI] ERROR: pop_arp_reply returned null despite hasArpReply=true\n", .{});
        return -1;
    };
    defer gpa.free(arp_frame); // Free after copying

    // Validate buffer size
    if (arp_frame.len > out_buffer_size) {
        std.debug.print("[TapTun C FFI] ERROR: ARP reply too large: {d} > {d}\n", .{ arp_frame.len, out_buffer_size });
        return -2; // Buffer too small
    }

    // Copy ARP reply to output buffer
    @memcpy(out_frame[0..arp_frame.len], arp_frame);

    std.debug.print("[TapTun C FFI] ✅ pop_arp_reply: {d} bytes ARP reply ready to send\n", .{arp_frame.len});

    return @intCast(arp_frame.len);
}
