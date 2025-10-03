//! Integration test for macOS utun device (requires sudo)

const std = @import("std");
const macos = @import("platform/macos.zig");

test "open utun device" {
    const allocator = std.testing.allocator;
    
    std.debug.print("\n=== Testing macOS utun Device ===\n", .{});
    std.debug.print("Attempting to open utun device...\n", .{});
    
    var device = macos.MacOSUtunDevice.open(allocator, null) catch |err| {
        std.debug.print("❌ Error: {}\n", .{err});
        std.debug.print("Note: This test requires root privileges (sudo)\n", .{});
        return err;
    };
    defer device.close();
    
    const name = device.getName();
    std.debug.print("✅ Successfully opened: {s}\n", .{name});
    std.debug.print("   Unit number: {}\n", .{device.getUnit()});
    std.debug.print("   MTU: {}\n", .{device.mtu});
    std.debug.print("   FD: {}\n", .{device.fd});
    
    try std.testing.expect(std.mem.startsWith(u8, name, "utun"));
    try std.testing.expect(device.fd >= 0);
    
    std.debug.print("\n🎉 Test passed! Device created successfully.\n", .{});
    std.debug.print("\nTo configure this device, run:\n", .{});
    std.debug.print("  sudo ifconfig {s} 10.0.0.1 10.0.0.2 netmask 255.255.255.0\n\n", .{name});
}
