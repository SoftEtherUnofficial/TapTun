//! FreeBSD /dev/tun implementation
//! This is a stub implementation - to be fully implemented

const std = @import("std");

// Platform-specific stubs for FreeBSD
pub const FreeBSDDevice = struct {
    pub fn init() !FreeBSDDevice {
        return error.UnsupportedPlatform;
    }
};
