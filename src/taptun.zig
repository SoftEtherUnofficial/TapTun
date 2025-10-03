//! ZigTapTun - Cross-Platform TAP/TUN Library
//!
//! This library provides L2↔L3 protocol translation for TAP/TUN devices.
//! Currently implements the core translation logic with ARP handling.
//!
//! TODO: Device abstraction layer
//! TODO: Platform-specific implementations (macOS, Linux, Windows, FreeBSD)
//! TODO: PacketQueue implementation

const std = @import("std");

// Core modules (implemented)
pub const L2L3Translator = @import("translator.zig").L2L3Translator;
pub const ArpHandler = @import("arp.zig").ArpHandler;

// Public types for L2L3 translation
pub const TranslatorOptions = struct {
    our_mac: [6]u8,
    learn_ip: bool = true,
    learn_gateway_mac: bool = true,
    handle_arp: bool = true,
    arp_timeout_ms: u32 = 60000,
    verbose: bool = false,
};

/// Error set for translation operations
pub const TapTunError = error{
    InvalidPacket,
    TranslationFailed,
};

test {
    std.testing.refAllDecls(@This());
}
