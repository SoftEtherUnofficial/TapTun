//! Simple standalone test for macOS utun device
//! Compile with: zig build-exe test_macos_utun.zig
//! Run with: sudo ./test_macos_utun

const std = @import("std");
const os = std.os;

// Inline the necessary definitions
const UTUN_CONTROL_NAME = "com.apple.net.utun_control";
const UTUN_OPT_IFNAME = 2;
const PF_SYSTEM = 32;
const AF_SYSTEM = 32;
const AF_SYS_CONTROL = 2;
const SYSPROTO_CONTROL = 2;
const CTLIOCGINFO: u32 = 0xc0644e03;
const MAX_KCTL_NAME = 96;

const ctl_info = extern struct {
    ctl_id: u32,
    ctl_name: [MAX_KCTL_NAME]u8,
};

const sockaddr_ctl = extern struct {
    sc_len: u8,
    sc_family: u8,
    ss_sysaddr: u16,
    sc_id: u32,
    sc_unit: u32,
    sc_reserved: [5]u32,
};

pub fn main() !void {
    std.debug.print("=== macOS utun Device Test ===\n\n", .{});
    std.debug.print("Opening utun device...\n", .{});

    // Create PF_SYSTEM socket
    const fd = os.socket(PF_SYSTEM, os.SOCK.DGRAM, SYSPROTO_CONTROL) catch |err| {
        std.debug.print("❌ Error creating socket: {}\n", .{err});
        std.debug.print("\nThis requires root privileges. Run with:\n", .{});
        std.debug.print("  sudo ./test_macos_utun\n", .{});
        return err;
    };
    defer os.close(fd);

    std.debug.print("✅ Socket created (fd={})\n", .{fd});

    // Get utun control ID
    var info = std.mem.zeroes(ctl_info);
    @memcpy(info.ctl_name[0..UTUN_CONTROL_NAME.len], UTUN_CONTROL_NAME);

    const ioctl_result = os.system.ioctl(fd, CTLIOCGINFO, @intFromPtr(&info));
    if (ioctl_result != 0) {
        std.debug.print("❌ Error getting control info: {}\n", .{ioctl_result});
        return error.DeviceNotFound;
    }

    std.debug.print("✅ Got utun control ID: {}\n", .{info.ctl_id});

    // Prepare sockaddr_ctl
    var addr = std.mem.zeroes(sockaddr_ctl);
    addr.sc_len = @sizeOf(sockaddr_ctl);
    addr.sc_family = AF_SYSTEM;
    addr.ss_sysaddr = AF_SYS_CONTROL;
    addr.sc_id = info.ctl_id;
    addr.sc_unit = 0; // Auto-allocate

    // Connect to utun control
    const addr_ptr: *const os.sockaddr = @ptrCast(&addr);
    os.connect(fd, addr_ptr, @sizeOf(sockaddr_ctl)) catch |err| {
        std.debug.print("❌ Error connecting: {}\n", .{err});
        return err;
    };

    std.debug.print("✅ Connected to utun control\n", .{});

    // Get interface name
    var ifname: [16]u8 = undefined;
    var ifname_len: u32 = ifname.len;

    const getsockopt_result = os.system.getsockopt(
        fd,
        SYSPROTO_CONTROL,
        UTUN_OPT_IFNAME,
        &ifname,
        &ifname_len,
    );
    if (getsockopt_result != 0) {
        std.debug.print("❌ Error getting interface name: {}\n", .{getsockopt_result});
        return error.InvalidConfiguration;
    }

    const name = ifname[0..ifname_len];
    std.debug.print("✅ Interface name: {s}\n\n", .{name});

    std.debug.print("🎉 Success! utun device created!\n\n", .{});
    std.debug.print("To configure the interface, run:\n", .{});
    std.debug.print("  sudo ifconfig {s} 10.0.0.1 10.0.0.2 netmask 255.255.255.0\n\n", .{name});
    std.debug.print("Then test with:\n", .{});
    std.debug.print("  ping 10.0.0.2\n", .{});
}
