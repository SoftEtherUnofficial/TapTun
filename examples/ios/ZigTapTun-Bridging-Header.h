//
//  ZigTapTun-Bridging-Header.h
//  iOS Bridge to ZigTapTun Native Library
//
//  This header exposes the Zig C API to Swift code for use in
//  Network Extension (NEPacketTunnelProvider) implementations.
//

#ifndef ZigTapTun_Bridging_Header_h
#define ZigTapTun_Bridging_Header_h

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ═══════════════════════════════════════════════════════════════════════════
// Type Definitions
// ═══════════════════════════════════════════════════════════════════════════

/// Opaque handle to ZigTapTun device
typedef void* ZigTapTunHandle;

/// Error codes
typedef enum {
    ZigTapTunError_Success = 0,
    ZigTapTunError_OutOfMemory = -1,
    ZigTapTunError_InvalidParameter = -2,
    ZigTapTunError_DeviceNotActive = -3,
    ZigTapTunError_BufferTooSmall = -4,
    ZigTapTunError_PacketTooLarge = -5,
    ZigTapTunError_QueueFull = -6,
    ZigTapTunError_WouldBlock = -7,
    ZigTapTunError_Unknown = -99,
} ZigTapTunError;

// ═══════════════════════════════════════════════════════════════════════════
// Device Management
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Create iOS VPN device
 * @param name Device name (can be NULL for default)
 * @return Handle to device, or NULL on error
 */
ZigTapTunHandle _Nullable zig_taptun_ios_create(const char* _Nullable name);

/**
 * Destroy iOS VPN device and free resources
 * @param handle Device handle
 */
void zig_taptun_ios_destroy(ZigTapTunHandle _Nonnull handle);

/**
 * Activate device (call when VPN tunnel starts)
 * @param handle Device handle
 */
void zig_taptun_ios_activate(ZigTapTunHandle _Nonnull handle);

/**
 * Deactivate device (call when VPN tunnel stops)
 * @param handle Device handle
 */
void zig_taptun_ios_deactivate(ZigTapTunHandle _Nonnull handle);

// ═══════════════════════════════════════════════════════════════════════════
// Packet I/O
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Enqueue packet received from NEPacketFlow
 * Call this when NEPacketFlow provides a packet to send through the tunnel
 * @param handle Device handle
 * @param data Packet data
 * @param length Packet length in bytes
 * @return Error code
 */
ZigTapTunError zig_taptun_ios_enqueue_read(
    ZigTapTunHandle _Nonnull handle,
    const uint8_t* _Nonnull data,
    size_t length
);

/**
 * Dequeue packet to send via NEPacketFlow
 * Call this periodically to get packets that should be sent through NEPacketFlow
 * @param handle Device handle
 * @param buffer Buffer to receive packet data
 * @param buffer_size Size of buffer
 * @param out_length Output: actual packet length written
 * @return Error code (WouldBlock if no packets available)
 */
ZigTapTunError zig_taptun_ios_dequeue_write(
    ZigTapTunHandle _Nonnull handle,
    uint8_t* _Nonnull buffer,
    size_t buffer_size,
    size_t* _Nonnull out_length
);

/**
 * Get number of packets waiting to be sent
 * Use this to know when to call dequeue_write
 * @param handle Device handle
 * @return Number of pending packets
 */
size_t zig_taptun_ios_pending_write_count(ZigTapTunHandle _Nonnull handle);

// ═══════════════════════════════════════════════════════════════════════════
// Configuration
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Set device MTU
 * @param handle Device handle
 * @param mtu MTU value (68-65535)
 * @return Error code
 */
ZigTapTunError zig_taptun_ios_set_mtu(
    ZigTapTunHandle _Nonnull handle,
    uint32_t mtu
);

/**
 * Set IPv4 address and netmask
 * @param handle Device handle
 * @param address IPv4 address (network byte order)
 * @param netmask IPv4 netmask (network byte order)
 * @return Error code
 */
ZigTapTunError zig_taptun_ios_set_ipv4(
    ZigTapTunHandle _Nonnull handle,
    uint32_t address,
    uint32_t netmask
);

/**
 * Set IPv6 address and prefix length
 * @param handle Device handle
 * @param address IPv6 address (16 bytes)
 * @param prefix_len Prefix length (0-128)
 * @return Error code
 */
ZigTapTunError zig_taptun_ios_set_ipv6(
    ZigTapTunHandle _Nonnull handle,
    const uint8_t* _Nonnull address,
    uint8_t prefix_len
);

#ifdef __cplusplus
}
#endif

#endif /* ZigTapTun_Bridging_Header_h */
