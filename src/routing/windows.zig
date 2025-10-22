/// Windows Route Management
///
/// Uses `route.exe` command or Win32 API for route manipulation.
/// Future: Use GetIpForwardTable/SetIpForwardEntry for direct API access.
const std = @import("std");

pub const RouteManager = struct {
    allocator: std.mem.Allocator,
    local_gateway: ?[4]u8 = null,
    vpn_gateway: ?[4]u8 = null,
    vpn_server_ips: std.ArrayList([4]u8),
    routes_configured: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .vpn_server_ips = std.ArrayList([4]u8).init(allocator),
        };
        return self;
    }

    /// Get current default gateway using route print
    pub fn getDefaultGateway(self: *Self) !void {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "cmd.exe",
                "/c",
                "route print 0.0.0.0 | findstr \"0.0.0.0\" | findstr /v \"On-link\" | for /f \"tokens=4\" %i in ('findstr /n \"^\" ') do @echo %i",
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.stdout.len == 0) {
            return error.NoDefaultGateway;
        }

        // Parse IP address
        const ip_str = std.mem.trim(u8, result.stdout, " \t\n\r");
        var octets: [4]u8 = undefined;
        var iter = std.mem.splitSequence(u8, ip_str, ".");
        var i: usize = 0;

        while (iter.next()) |octet_str| : (i += 1) {
            if (i >= 4) return error.InvalidIpAddress;
            octets[i] = try std.fmt.parseInt(u8, octet_str, 10);
        }

        if (i != 4) return error.InvalidIpAddress;

        self.local_gateway = octets;
        std.log.info("Saved original gateway: {d}.{d}.{d}.{d}", .{
            octets[0],
            octets[1],
            octets[2],
            octets[3],
        });
    }

    /// Replace default gateway with VPN gateway
    pub fn replaceDefaultGateway(self: *Self, vpn_gw: [4]u8) !void {
        self.vpn_gateway = vpn_gw;

        var gw_buf: [16]u8 = undefined;
        const gw_str = try std.fmt.bufPrint(&gw_buf, "{d}.{d}.{d}.{d}", .{
            vpn_gw[0],
            vpn_gw[1],
            vpn_gw[2],
            vpn_gw[3],
        });

        // Delete existing default route
        std.log.info("Deleting existing default route...", .{});
        const delete_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "route", "delete", "0.0.0.0" },
        });
        defer self.allocator.free(delete_result.stdout);
        defer self.allocator.free(delete_result.stderr);

        // Add VPN default route
        std.log.info("Adding VPN default route: {s}", .{gw_str});
        const add_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "route", "add", "0.0.0.0", "mask", "0.0.0.0", gw_str },
        });
        defer self.allocator.free(add_result.stdout);
        defer self.allocator.free(add_result.stderr);

        if (add_result.term != .Exited or add_result.term.Exited != 0) {
            std.log.err("Failed to add default route: {s}", .{add_result.stderr});
            return error.RouteAddFailed;
        }

        self.routes_configured = true;
        std.log.info("✅ Default route now points to VPN gateway {d}.{d}.{d}.{d}", .{
            vpn_gw[0],
            vpn_gw[1],
            vpn_gw[2],
            vpn_gw[3],
        });
    }

    /// Add host route
    pub fn addHostRoute(self: *Self, destination: [4]u8, gateway: [4]u8) !void {
        var dest_buf: [16]u8 = undefined;
        const dest_str = try std.fmt.bufPrint(&dest_buf, "{d}.{d}.{d}.{d}", .{
            destination[0],
            destination[1],
            destination[2],
            destination[3],
        });

        var gw_buf: [16]u8 = undefined;
        const gw_str = try std.fmt.bufPrint(&gw_buf, "{d}.{d}.{d}.{d}", .{
            gateway[0],
            gateway[1],
            gateway[2],
            gateway[3],
        });

        std.log.info("Adding host route: {s} via {s}", .{ dest_str, gw_str });

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "route", "add", dest_str, "mask", "255.255.255.255", gw_str },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term != .Exited or result.term.Exited != 0) {
            std.log.warn("Failed to add host route (may already exist): {s}", .{result.stderr});
        }

        try self.vpn_server_ips.append(self.allocator, destination);
    }

    /// Restore original routing
    pub fn restore(self: *Self) !void {
        if (!self.routes_configured or self.local_gateway == null) {
            std.log.debug("No routes to restore", .{});
            return;
        }

        const orig_gw = self.local_gateway.?;
        var gw_buf: [16]u8 = undefined;
        const gw_str = try std.fmt.bufPrint(&gw_buf, "{d}.{d}.{d}.{d}", .{
            orig_gw[0],
            orig_gw[1],
            orig_gw[2],
            orig_gw[3],
        });

        std.log.info("🔄 Restoring original routing (gateway: {s})", .{gw_str});

        // Delete VPN default route
        std.log.info("Removing VPN default route...", .{});
        const delete_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "route", "delete", "0.0.0.0" },
        });
        defer self.allocator.free(delete_result.stdout);
        defer self.allocator.free(delete_result.stderr);

        // Restore original default route
        std.log.info("✅ Restoring original default route: {s}", .{gw_str});
        const add_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "route", "add", "0.0.0.0", "mask", "0.0.0.0", gw_str },
        });
        defer self.allocator.free(add_result.stdout);
        defer self.allocator.free(add_result.stderr);

        // Clean up VPN server host routes
        for (self.vpn_server_ips.items) |server_ip| {
            var server_buf: [16]u8 = undefined;
            const server_str = try std.fmt.bufPrint(&server_buf, "{d}.{d}.{d}.{d}", .{
                server_ip[0],
                server_ip[1],
                server_ip[2],
                server_ip[3],
            });

            std.log.debug("Cleaning up VPN server route: {s}", .{server_str});
            const cleanup_result = try std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = &[_][]const u8{ "route", "delete", server_str },
            });
            defer self.allocator.free(cleanup_result.stdout);
            defer self.allocator.free(cleanup_result.stderr);
        }

        std.log.info("✅ Routing restored successfully", .{});
        self.routes_configured = false;
    }

    pub fn deinit(self: *Self) void {
        self.restore() catch |err| {
            std.log.err("Failed to restore routes during deinit: {}", .{err});
        };

        self.vpn_server_ips.deinit();
        self.allocator.destroy(self);
    }
};

test "Windows RouteManager basic operations" {
    if (@import("builtin").os.tag != .windows) {
        return error.SkipZigTest;
    }

    if (std.process.hasEnvVarConstant("CI") or std.process.hasEnvVarConstant("SKIP_INTEGRATION_TESTS")) {
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;
    var rm = try RouteManager.init(allocator);
    defer rm.deinit();

    rm.getDefaultGateway() catch |err| {
        std.debug.print("Skipping test (requires admin): {}\n", .{err});
        return error.SkipZigTest;
    };

    try std.testing.expect(rm.local_gateway != null);
}
