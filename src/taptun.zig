//! ZigTapTun - Cross-Platform TAP/TUN Library
//!
//! This library provides a unified interface for TAP/TUN devices across
//! macOS, Linux, Windows, and FreeBSD, with automatic L2↔L3 translation.

const std = @import("std");
const builtin = @import("builtin");

// Platform-specific implementations
const macos = if (builtin.os.tag == .macos) @import("platform/macos.zig") else struct {};
const linux = if (builtin.os.tag == .linux) @import("platform/linux.zig") else struct {};
const windows = if (builtin.os.tag == .windows) @import("platform/windows.zig") else struct {};
const freebsd = if (builtin.os.tag == .freebsd) @import("platform/freebsd.zig") else struct {};

// Core modules
pub const Device = @import("device.zig").Device;
pub const TunDevice = @import("device.zig").TunDevice;
pub const TapDevice = @import("device.zig").TapDevice;
pub const L2L3Translator = @import("translator.zig").L2L3Translator;
pub const ArpHandler = @import("arp.zig").ArpHandler;
pub const PacketQueue = @import("queue.zig").PacketQueue;

// Types
pub const DeviceType = enum {
    tun, // Layer 3 (IP packets)
    tap, // Layer 2 (Ethernet frames)
};

pub const DeviceOptions = struct {
    device_type: DeviceType,
    name: ?[]const u8 = null, // null = auto-allocate
    mtu: u16 = 1500,
    enable_l2_translation: bool = false, // TUN only: enable automatic L2↔L3 translation
    persistent: bool = false, // Linux only: create persistent interface
    owner_uid: ?u32 = null, // Linux only: set interface owner
    group_gid: ?u32 = null, // Linux only: set interface group
};

pub const IpConfig = struct {
    ip: std.net.Address,
    netmask: std.net.Address,
    gateway: ?std.net.Address = null,
    mtu: ?u16 = null,
};

pub const TranslatorOptions = struct {
    our_mac: [6]u8,
    learn_ip: bool = true,
    learn_gateway_mac: bool = true,
    handle_arp: bool = true,
    arp_timeout_ms: u32 = 60000,
    verbose: bool = false,
};

pub const DeviceStats = struct {
    packets_received: u64,
    packets_sent: u64,
    bytes_received: u64,
    bytes_sent: u64,
    packets_dropped: u64,
    errors: u64,
};

/// Error set for TAP/TUN operations
pub const TapTunError = error{
    DeviceNotFound,
    DeviceInUse,
    PermissionDenied,
    InvalidConfiguration,
    UnsupportedPlatform,
    TranslationFailed,
    PacketTooLarge,
    InvalidPacket,
    QueueFull,
};

test {
    std.testing.refAllDecls(@This());
}
