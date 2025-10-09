/// Route Management Module
///
/// Platform-agnostic routing table management for VPN applications.
/// Supports macOS, Linux, and Windows (future).
///
/// Features:
/// - Get/set default gateway
/// - Add/remove host routes
/// - Save/restore routing state
/// - Platform-specific implementations
const std = @import("std");
const builtin = @import("builtin");

// Platform-specific implementations
const macos = @import("routing/macos.zig");
const linux = if (builtin.os.tag == .linux) @import("routing/linux.zig") else void;
const windows = if (builtin.os.tag == .windows) @import("routing/windows.zig") else void;

pub const RouteError = error{
    NoDefaultGateway,
    InvalidIpAddress,
    RouteAddFailed,
    RouteDeleteFailed,
    CommandFailed,
    PlatformNotSupported,
    PermissionDenied,
};

/// IPv4 address representation
pub const Ipv4Address = [4]u8;

/// Route entry
pub const Route = struct {
    destination: Ipv4Address,
    gateway: Ipv4Address,
    netmask: ?Ipv4Address = null,
    interface: ?[]const u8 = null,
};

/// Platform-agnostic Route Manager
pub const RouteManager = switch (builtin.os.tag) {
    .macos => macos.RouteManager,
    .linux => if (@hasDecl(@This(), "linux")) linux.RouteManager else UnsupportedRouteManager,
    .windows => if (@hasDecl(@This(), "windows")) windows.RouteManager else UnsupportedRouteManager,
    else => UnsupportedRouteManager,
};

/// Unsupported platform placeholder
const UnsupportedRouteManager = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*@This() {
        _ = allocator;
        return error.PlatformNotSupported;
    }

    pub fn getDefaultGateway(_: *@This()) !void {
        return error.PlatformNotSupported;
    }

    pub fn replaceDefaultGateway(_: *@This(), _: Ipv4Address) !void {
        return error.PlatformNotSupported;
    }

    pub fn addHostRoute(_: *@This(), _: Ipv4Address, _: Ipv4Address) !void {
        return error.PlatformNotSupported;
    }

    pub fn restore(_: *@This()) !void {
        return error.PlatformNotSupported;
    }

    pub fn deinit(_: *@This()) void {}
};

/// Format IPv4 address to string
pub fn formatIpv4(ip: Ipv4Address, writer: anytype) !void {
    try writer.print("{d}.{d}.{d}.{d}", .{ ip[0], ip[1], ip[2], ip[3] });
}

/// Parse IPv4 address from string
pub fn parseIpv4(str: []const u8) !Ipv4Address {
    var result: Ipv4Address = undefined;
    var iter = std.mem.splitSequence(u8, str, ".");
    var i: usize = 0;

    while (iter.next()) |octet_str| : (i += 1) {
        if (i >= 4) return error.InvalidIpAddress;
        result[i] = try std.fmt.parseInt(u8, octet_str, 10);
    }

    if (i != 4) return error.InvalidIpAddress;
    return result;
}

/// Format IPv4 address to buffer
pub fn ipv4ToString(ip: Ipv4Address, buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ ip[0], ip[1], ip[2], ip[3] });
}

test "parseIpv4" {
    const ip = try parseIpv4("192.168.1.1");
    try std.testing.expectEqual([4]u8{ 192, 168, 1, 1 }, ip);

    const ip2 = try parseIpv4("10.0.0.1");
    try std.testing.expectEqual([4]u8{ 10, 0, 0, 1 }, ip2);

    // Invalid IPs
    try std.testing.expectError(error.InvalidIpAddress, parseIpv4("192.168.1"));
    try std.testing.expectError(error.InvalidIpAddress, parseIpv4("192.168.1.1.1"));
}

test "ipv4ToString" {
    var buf: [16]u8 = undefined;
    const str = try ipv4ToString(.{ 192, 168, 1, 1 }, &buf);
    try std.testing.expectEqualStrings("192.168.1.1", str);
}
