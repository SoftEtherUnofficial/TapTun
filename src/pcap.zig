/// Packet Capture (PCAP) Writer
///
/// Simple PCAP file format writer for debugging and troubleshooting VPN traffic.
/// Captures Ethernet frames or raw IP packets to standard .pcap files
/// that can be analyzed with Wireshark or tcpdump.
///
/// PCAP Format: https://wiki.wireshark.org/Development/LibpcapFileFormat
const std = @import("std");

/// PCAP File Header (24 bytes)
const PcapHeader = packed struct {
    magic_number: u32 = 0xa1b2c3d4, // Magic number (big endian)
    version_major: u16 = 2, // Major version
    version_minor: u16 = 4, // Minor version
    thiszone: i32 = 0, // GMT to local correction
    sigfigs: u32 = 0, // Accuracy of timestamps
    snaplen: u32 = 65535, // Max packet length
    network: u32, // Data link type (1 = Ethernet, 101 = Raw IP)
};

/// PCAP Packet Header (16 bytes)
const PcapPacketHeader = packed struct {
    ts_sec: u32, // Timestamp seconds
    ts_usec: u32, // Timestamp microseconds
    incl_len: u32, // Number of bytes captured
    orig_len: u32, // Actual packet length
};

/// Link Layer Types
pub const LinkType = enum(u32) {
    ETHERNET = 1,
    RAW_IP = 101,
    LINUX_SLL = 113,
};

/// PCAP Writer
pub const PcapWriter = struct {
    file: std.fs.File,
    allocator: std.mem.Allocator,
    packet_count: usize = 0,
    bytes_written: usize = 0,

    const Self = @This();

    /// Create new PCAP file
    pub fn init(allocator: std.mem.Allocator, filepath: []const u8, link_type: LinkType) !*Self {
        const file = try std.fs.cwd().createFile(filepath, .{});
        const self = try allocator.create(Self);

        self.* = .{
            .file = file,
            .allocator = allocator,
        };

        // Write PCAP file header
        const header = PcapHeader{
            .network = @intFromEnum(link_type),
        };

        try self.file.writeAll(std.mem.asBytes(&header));
        self.bytes_written += @sizeOf(PcapHeader);

        std.log.info("📝 Created PCAP file: {s}", .{filepath});

        return self;
    }

    /// Write packet to PCAP file
    pub fn writePacket(self: *Self, data: []const u8) !void {
        const now = std.time.microTimestamp();
        const ts_sec: u32 = @intCast(@divFloor(now, std.time.us_per_s));
        const ts_usec: u32 = @intCast(@mod(now, std.time.us_per_s));

        const packet_header = PcapPacketHeader{
            .ts_sec = ts_sec,
            .ts_usec = ts_usec,
            .incl_len = @intCast(data.len),
            .orig_len = @intCast(data.len),
        };

        // Write packet header
        try self.file.writeAll(std.mem.asBytes(&packet_header));

        // Write packet data
        try self.file.writeAll(data);

        self.packet_count += 1;
        self.bytes_written += @sizeOf(PcapPacketHeader) + data.len;

        if (self.packet_count % 100 == 0) {
            std.log.debug("📊 Captured {d} packets ({d} bytes)", .{
                self.packet_count,
                self.bytes_written,
            });
        }
    }

    /// Flush buffered data
    pub fn flush(self: *Self) !void {
        try self.file.sync();
    }

    /// Get capture statistics
    pub fn getStats(self: Self) CaptureStats {
        return .{
            .packet_count = self.packet_count,
            .bytes_written = self.bytes_written,
        };
    }

    pub fn deinit(self: *Self) void {
        self.flush() catch |err| {
            std.log.warn("Failed to flush PCAP file: {}", .{err});
        };

        std.log.info("✅ PCAP capture complete: {d} packets, {d} bytes", .{
            self.packet_count,
            self.bytes_written,
        });

        self.file.close();
        self.allocator.destroy(self);
    }
};

/// Capture statistics
pub const CaptureStats = struct {
    packet_count: usize,
    bytes_written: usize,
};

/// Packet Capture Session with automatic rotation
pub const CaptureSession = struct {
    allocator: std.mem.Allocator,
    base_filename: []const u8,
    link_type: LinkType,
    max_file_size: usize,
    current_writer: ?*PcapWriter = null,
    file_index: usize = 0,

    const Self = @This();

    /// Create new capture session with file rotation
    pub fn init(
        allocator: std.mem.Allocator,
        base_filename: []const u8,
        link_type: LinkType,
        max_file_size: usize,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .base_filename = base_filename,
            .link_type = link_type,
            .max_file_size = max_file_size,
        };
        return self;
    }

    /// Start capturing (creates first file)
    pub fn start(self: *Self) !void {
        try self.rotateFile();
    }

    /// Write packet (with automatic rotation)
    pub fn writePacket(self: *Self, data: []const u8) !void {
        // Create first file if needed
        if (self.current_writer == null) {
            try self.start();
        }

        const writer = self.current_writer.?;

        // Check if rotation needed
        if (writer.bytes_written + data.len > self.max_file_size) {
            try self.rotateFile();
        }

        try self.current_writer.?.writePacket(data);
    }

    /// Rotate to new file
    fn rotateFile(self: *Self) !void {
        // Close current writer
        if (self.current_writer) |writer| {
            writer.deinit();
        }

        // Generate new filename
        var filename_buf: [256]u8 = undefined;
        const filename = try std.fmt.bufPrint(&filename_buf, "{s}.{d}.pcap", .{
            self.base_filename,
            self.file_index,
        });

        const filename_owned = try self.allocator.dupe(u8, filename);
        defer self.allocator.free(filename_owned);

        std.log.info("🔄 Rotating to new capture file: {s}", .{filename_owned});

        // Create new writer
        self.current_writer = try PcapWriter.init(self.allocator, filename_owned, self.link_type);
        self.file_index += 1;
    }

    /// Get total statistics
    pub fn getTotalStats(self: Self) CaptureStats {
        if (self.current_writer) |writer| {
            return writer.getStats();
        }
        return .{ .packet_count = 0, .bytes_written = 0 };
    }

    pub fn deinit(self: *Self) void {
        if (self.current_writer) |writer| {
            writer.deinit();
        }
        self.allocator.destroy(self);
    }
};

/// Helper: Create Ethernet frame header
pub fn createEthernetHeader(dst_mac: [6]u8, src_mac: [6]u8, ethertype: u16) [14]u8 {
    var header: [14]u8 = undefined;
    @memcpy(header[0..6], &dst_mac);
    @memcpy(header[6..12], &src_mac);
    std.mem.writeInt(u16, header[12..14], ethertype, .big);
    return header;
}

test "PCAP file creation" {
    const allocator = std.testing.allocator;

    var writer = try PcapWriter.init(allocator, "test.pcap", .ETHERNET);
    defer writer.deinit();

    // Write test packet
    const test_packet = [_]u8{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, // Dst MAC
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, // Src MAC
        0x08, 0x00, // EtherType (IPv4)
        // ... rest of packet
    };

    try writer.writePacket(&test_packet);

    const stats = writer.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.packet_count);

    // Cleanup
    std.fs.cwd().deleteFile("test.pcap") catch {};
}

test "Capture session with rotation" {
    const allocator = std.testing.allocator;

    var session = try CaptureSession.init(
        allocator,
        "test_capture",
        .ETHERNET,
        1024, // 1KB max file size for testing
    );
    defer session.deinit();

    try session.start();

    // Write packets that trigger rotation
    const large_packet = [_]u8{0xAB} ** 512;
    try session.writePacket(&large_packet); // File 0
    try session.writePacket(&large_packet); // File 0
    try session.writePacket(&large_packet); // Should rotate to File 1

    try std.testing.expectEqual(@as(usize, 2), session.file_index);

    // Cleanup
    std.fs.cwd().deleteFile("test_capture.0.pcap") catch {};
    std.fs.cwd().deleteFile("test_capture.1.pcap") catch {};
}

test "Ethernet header creation" {
    const dst_mac = [_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
    const src_mac = [_]u8{ 0x00, 0x11, 0x22, 0x33, 0x44, 0x55 };
    const ethertype: u16 = 0x0800; // IPv4

    const header = createEthernetHeader(dst_mac, src_mac, ethertype);

    try std.testing.expectEqual(@as(usize, 14), header.len);
    try std.testing.expectEqual(@as(u8, 0xff), header[0]);
    try std.testing.expectEqual(@as(u8, 0x00), header[6]);
    try std.testing.expectEqual(@as(u16, 0x0800), std.mem.readInt(u16, header[12..14], .big));
}
