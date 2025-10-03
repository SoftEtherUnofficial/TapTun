//! Linux /dev/net/tun implementation
//! This is a stub implementation - to be fully implemented

const std = @import("std");

// Platform-specific stubs for Linux
pub const LinuxDevice = struct {
    pub fn init() !LinuxDevice {
        return error.UnsupportedPlatform;
    }
};
