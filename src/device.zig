//! Device abstraction for TAP/TUN interfaces
//! This is a stub implementation - to be fully implemented

const std = @import("std");
const taptun = @import("taptun.zig");

pub const Device = struct {
    // Stub implementation
    pub fn init(allocator: std.mem.Allocator, options: taptun.DeviceOptions) !Device {
        _ = allocator;
        _ = options;
        return error.UnsupportedPlatform;
    }

    pub fn deinit(self: *Device) void {
        _ = self;
    }
};

pub const TunDevice = struct {
    // Stub implementation
    pub fn init(allocator: std.mem.Allocator, options: taptun.DeviceOptions) !TunDevice {
        _ = allocator;
        _ = options;
        return error.UnsupportedPlatform;
    }

    pub fn deinit(self: *TunDevice) void {
        _ = self;
    }
};

pub const TapDevice = struct {
    // Stub implementation
    pub fn init(allocator: std.mem.Allocator, options: taptun.DeviceOptions) !TapDevice {
        _ = allocator;
        _ = options;
        return error.UnsupportedPlatform;
    }

    pub fn deinit(self: *TapDevice) void {
        _ = self;
    }
};
