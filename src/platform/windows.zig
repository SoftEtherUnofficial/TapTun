//! Windows TAP-Windows implementation
//! This is a stub implementation - to be fully implemented

const std = @import("std");

// Platform-specific stubs for Windows
pub const WindowsDevice = struct {
    pub fn init() !WindowsDevice {
        return error.UnsupportedPlatform;
    }
};
