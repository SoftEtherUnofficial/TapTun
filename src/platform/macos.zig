//! macOS utun implementation
//! This is a stub implementation - to be fully implemented

const std = @import("std");

// Platform-specific stubs for macOS
pub const MacOSDevice = struct {
    pub fn init() !MacOSDevice {
        return error.UnsupportedPlatform;
    }
};
