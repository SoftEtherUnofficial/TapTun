//! L2↔L3 Protocol Translator
//!
//! Handles bidirectional conversion between Layer 2 (Ethernet frames) and Layer 3 (IP packets).
//! This is critical for using TUN devices (L3) with protocols that expect TAP devices (L2).

const std = @import("std");
const taptun = @import("taptun.zig");
const ArpHandler = @import("arp.zig").ArpHandler;

pub const L2L3Translator = struct {
    allocator: std.mem.Allocator,
    options: taptun.TranslatorOptions,

    // Learned network information
    our_ip: ?u32, // Our IP address (learned from outgoing packets)
    gateway_ip: ?u32, // Gateway IP address
    gateway_mac: ?[6]u8, // Gateway MAC address (learned from ARP)
    last_gateway_learn: i64, // Timestamp of last gateway MAC learn

    // ARP handling
    arp_handler: ArpHandler,

    // ARP reply queue (for replies that need to be sent back to VPN)
    arp_reply_queue: std.ArrayList([]const u8),
    pending_arp_ips: std.AutoHashMap(u32, void), // Track IPs with pending replies
    packets_translated_l2_to_l3: u64,
    packets_translated_l3_to_l2: u64,
    arp_requests_handled: u64,
    arp_replies_learned: u64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: taptun.TranslatorOptions) !Self {
        return .{
            .allocator = allocator,
            .options = options,
            .our_ip = null,
            .gateway_ip = null,
            .gateway_mac = null,
            .last_gateway_learn = 0,
            .arp_handler = try ArpHandler.init(allocator, options.our_mac),
            .arp_reply_queue = std.ArrayList([]const u8){},
            .pending_arp_ips = std.AutoHashMap(u32, void).init(allocator),
            .packets_translated_l2_to_l3 = 0,
            .packets_translated_l3_to_l2 = 0,
            .arp_requests_handled = 0,
            .arp_replies_learned = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all queued ARP replies
        for (self.arp_reply_queue.items) |reply| {
            self.allocator.free(reply);
        }
        self.arp_reply_queue.deinit(self.allocator);
        self.pending_arp_ips.deinit();
        self.arp_handler.deinit();
    }

    /// Convert IP packet (L3) to Ethernet frame (L2)
    /// Used when sending packets from TUN device to network/VPN that expects Ethernet frames
    pub fn ipToEthernet(self: *Self, ip_packet: []const u8) ![]const u8 {
        if (ip_packet.len == 0) return error.InvalidPacket;

        // Learn our IP from source address if enabled
        if (self.options.learn_ip and self.our_ip == null) {
            if (ip_packet.len >= 20 and (ip_packet[0] & 0xF0) == 0x40) { // IPv4
                const src_ip = std.mem.readInt(u32, ip_packet[12..16], .big);
                // Ignore link-local addresses (169.254.x.x)
                if ((src_ip & 0xFFFF0000) != 0xA9FE0000) {
                    self.our_ip = src_ip;
                    if (self.options.verbose) {
                        std.debug.print("[L2L3] Learned our IP: {}.{}.{}.{}\n", .{
                            (src_ip >> 24) & 0xFF, (src_ip >> 16) & 0xFF,
                            (src_ip >> 8) & 0xFF,  src_ip & 0xFF,
                        });
                    }
                }
            }
        }

        // Determine EtherType and destination MAC
        var ethertype: u16 = undefined;
        var dest_mac: [6]u8 = undefined;

        if (ip_packet.len > 0 and (ip_packet[0] & 0xF0) == 0x40) {
            // IPv4 packet
            ethertype = 0x0800;

            // Use learned gateway MAC if available, otherwise broadcast
            if (self.gateway_mac) |gw_mac| {
                dest_mac = gw_mac;
            } else {
                @memset(&dest_mac, 0xFF); // Broadcast
            }
        } else if (ip_packet.len > 0 and (ip_packet[0] & 0xF0) == 0x60) {
            // IPv6 packet
            ethertype = 0x86DD;
            @memset(&dest_mac, 0xFF); // Broadcast for IPv6
        } else {
            return error.InvalidPacket;
        }

        // Build Ethernet frame: [6 dest MAC][6 src MAC][2 EtherType][payload]
        const frame_size = 14 + ip_packet.len;
        const frame = try self.allocator.alloc(u8, frame_size);
        errdefer self.allocator.free(frame);

        @memcpy(frame[0..6], &dest_mac); // Destination MAC
        @memcpy(frame[6..12], &self.options.our_mac); // Source MAC
        std.mem.writeInt(u16, frame[12..14], ethertype, .big); // EtherType
        @memcpy(frame[14..], ip_packet); // IP packet

        self.packets_translated_l3_to_l2 += 1;

        if (self.options.verbose) {
            std.debug.print("[L2L3] L3→L2: {} bytes IP → {} bytes Ethernet (type=0x{X:0>4})\n", .{ ip_packet.len, frame_size, ethertype });
        }

        return frame;
    }

    /// Convert Ethernet frame (L2) to IP packet (L3)
    /// Used when receiving Ethernet frames from network/VPN to write to TUN device
    /// Returns null if frame was handled internally (e.g., ARP)
    pub fn ethernetToIp(self: *Self, eth_frame: []const u8) !?[]const u8 {
        if (eth_frame.len < 14) return error.InvalidPacket;

        const ethertype = std.mem.readInt(u16, eth_frame[12..14], .big);

        // Handle ARP packets
        if (ethertype == 0x0806 and self.options.handle_arp) {
            return try self.handleArpFrame(eth_frame);
        }

        // Extract IP packet (strip 14-byte Ethernet header)
        var ip_packet: []const u8 = undefined;

        if (ethertype == 0x0800 or ethertype == 0x86DD) {
            // IPv4 or IPv6 - strip Ethernet header
            ip_packet = eth_frame[14..];
        } else {
            // Unknown EtherType - ignore
            if (self.options.verbose) {
                std.debug.print("[L2L3] Ignoring unknown EtherType: 0x{X:0>4}\n", .{ethertype});
            }
            return null;
        }

        // Allocate copy of IP packet
        const result = try self.allocator.alloc(u8, ip_packet.len);
        @memcpy(result, ip_packet);

        self.packets_translated_l2_to_l3 += 1;

        if (self.options.verbose) {
            std.debug.print("[L2L3] L2→L3: {} bytes Ethernet → {} bytes IP\n", .{ eth_frame.len, ip_packet.len });
        }

        return result;
    }

    /// Handle incoming ARP frame
    fn handleArpFrame(self: *Self, eth_frame: []const u8) !?[]const u8 {
        if (eth_frame.len < 42) return error.InvalidPacket; // Min ARP packet size

        const arp_data = eth_frame[14..]; // Skip Ethernet header
        const opcode = std.mem.readInt(u16, arp_data[6..8], .big);

        // Learn gateway MAC from ARP replies (opcode=2)
        if (opcode == 2 and self.options.learn_gateway_mac) {
            const sender_ip = std.mem.readInt(u32, arp_data[14..18], .big);

            // Check if this is from our gateway (typically x.x.x.1)
            if (self.gateway_ip) |gw_ip| {
                if (sender_ip == gw_ip) {
                    var new_mac: [6]u8 = undefined;
                    @memcpy(&new_mac, arp_data[8..14]);

                    const changed = if (self.gateway_mac) |old_mac|
                        !std.mem.eql(u8, &old_mac, &new_mac)
                    else
                        true;

                    if (changed) {
                        self.gateway_mac = new_mac;
                        self.last_gateway_learn = std.time.milliTimestamp();
                        self.arp_replies_learned += 1;

                        if (self.options.verbose) {
                            std.debug.print("[L2L3] Learned gateway MAC: {X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}\n", .{ new_mac[0], new_mac[1], new_mac[2], new_mac[3], new_mac[4], new_mac[5] });
                        }
                    }
                }
            }
        }

        // Handle ARP requests targeting our IP (opcode=1)
        if (opcode == 1 and self.our_ip != null) {
            const target_ip = std.mem.readInt(u32, arp_data[24..28], .big);

            if (target_ip == self.our_ip.?) {
                const sender_mac = arp_data[8..14];
                const sender_ip_bytes = arp_data[14..18];

                const reply = try self.arp_handler.buildArpReply(
                    self.our_ip.?,
                    sender_mac[0..6].*,
                    std.mem.readInt(u32, sender_ip_bytes, .big),
                );

                self.arp_requests_handled += 1;

                // Check if we already have a pending reply for this IP
                const already_pending = self.pending_arp_ips.contains(target_ip);

                // Limit queue size to prevent memory overflow
                const max_queue_size = 10;
                if (!already_pending and self.arp_reply_queue.items.len < max_queue_size) {
                    if (self.options.verbose) {
                        std.debug.print("[L2L3] Queuing ARP reply for {}.{}.{}.{} (queue: {}/{})\n", .{
                            (target_ip >> 24) & 0xFF,           (target_ip >> 16) & 0xFF,
                            (target_ip >> 8) & 0xFF,            target_ip & 0xFF,
                            self.arp_reply_queue.items.len + 1, max_queue_size,
                        });
                    }

                    // Queue the ARP reply and mark IP as pending
                    try self.arp_reply_queue.append(self.allocator, reply);
                    try self.pending_arp_ips.put(target_ip, {});
                } else {
                    // Already pending or queue full - free the duplicate reply
                    self.allocator.free(reply);
                    if (already_pending and self.options.verbose) {
                        std.debug.print("[L2L3] ⚠️  Duplicate ARP request for {}.{}.{}.{} (already queued)\n", .{
                            (target_ip >> 24) & 0xFF, (target_ip >> 16) & 0xFF,
                            (target_ip >> 8) & 0xFF,  target_ip & 0xFF,
                        });
                    } else if (self.options.verbose) {
                        std.debug.print("[L2L3] ⚠️  ARP queue full ({}/{}), dropping request for {}.{}.{}.{}\n", .{
                            self.arp_reply_queue.items.len, max_queue_size,
                            (target_ip >> 24) & 0xFF,       (target_ip >> 16) & 0xFF,
                            (target_ip >> 8) & 0xFF,        target_ip & 0xFF,
                        });
                    }
                }
                return null;
            }
        }

        // ARP packet not for us or already handled
        return null;
    }

    /// Manually set our IP address (alternative to learning)
    pub fn setOurIp(self: *Self, ip: u32) void {
        self.our_ip = ip;
    }

    /// Manually set gateway IP and MAC
    pub fn setGateway(self: *Self, ip: u32, mac: [6]u8) void {
        self.gateway_ip = ip;
        self.gateway_mac = mac;
        self.last_gateway_learn = std.time.milliTimestamp();
    }

    /// Get learned IP address
    pub fn getLearnedIp(self: *const Self) ?u32 {
        return self.our_ip;
    }

    /// Get learned gateway MAC
    pub fn getGatewayMac(self: *const Self) ?[6]u8 {
        return self.gateway_mac;
    }

    /// Check if there are pending ARP replies to send
    pub fn hasPendingArpReply(self: *const Self) bool {
        return self.arp_reply_queue.items.len > 0;
    }

    /// Get the next pending ARP reply (caller takes ownership and must free)
    pub fn popArpReply(self: *Self) ?[]const u8 {
        if (self.arp_reply_queue.items.len == 0) {
            return null;
        }
        const reply = self.arp_reply_queue.orderedRemove(0);

        // Extract target IP from ARP reply to remove from pending set
        // ARP reply format: dest_mac(6) + src_mac(6) + type(2) + arp_data(28+)
        // Target IP is at offset 24 (in ARP data section)
        if (reply.len >= 38) {
            const target_ip_bytes = reply[24..28];
            const target_ip = std.mem.readInt(u32, target_ip_bytes[0..4], .big);
            _ = self.pending_arp_ips.remove(target_ip);
        }

        return reply;
    }

    /// Get translation statistics
    pub fn getStats(self: *const Self) struct {
        l2_to_l3: u64,
        l3_to_l2: u64,
        arp_handled: u64,
        arp_learned: u64,
    } {
        return .{
            .l2_to_l3 = self.packets_translated_l2_to_l3,
            .l3_to_l2 = self.packets_translated_l3_to_l2,
            .arp_handled = self.arp_requests_handled,
            .arp_learned = self.arp_replies_learned,
        };
    }
};

test "L2L3Translator basic init" {
    const allocator = std.testing.allocator;

    var translator = try L2L3Translator.init(allocator, .{
        .our_mac = [_]u8{ 0x02, 0x00, 0x5E, 0x00, 0x00, 0x01 },
    });
    defer translator.deinit();

    try std.testing.expect(translator.our_ip == null);
    try std.testing.expect(translator.gateway_mac == null);
}
