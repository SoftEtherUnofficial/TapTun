//
//  zigtaptun_android.h
//  JNI Bridge Header for ZigTapTun Android Integration
//
//  This header defines the native interface between Java/Kotlin VpnService
//  and the ZigTapTun native library.
//

#ifndef ZIGTAPTUN_ANDROID_H
#define ZIGTAPTUN_ANDROID_H

#include <stdint.h>
#include <stddef.h>
#include <jni.h>

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
    ZigTapTunError_InvalidFileDescriptor = -3,
    ZigTapTunError_DeviceNotActive = -4,
    ZigTapTunError_DeviceClosed = -5,
    ZigTapTunError_BufferTooSmall = -6,
    ZigTapTunError_PacketTooLarge = -7,
    ZigTapTunError_ReadFailed = -8,
    ZigTapTunError_WriteFailed = -9,
    ZigTapTunError_PartialWrite = -10,
    ZigTapTunError_WouldBlock = -11,
    ZigTapTunError_Unknown = -99,
} ZigTapTunError;

// ═══════════════════════════════════════════════════════════════════════════
// Device Management
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Create Android VPN device from file descriptor
 * @param fd File descriptor from VpnService.Builder.establish()
 * @param mtu MTU value configured in VpnService.Builder
 * @return Handle to device, or NULL on error
 */
ZigTapTunHandle _Nullable zig_taptun_android_create(int32_t fd, uint32_t mtu);

/**
 * Destroy Android VPN device and free resources
 * @param handle Device handle
 */
void zig_taptun_android_destroy(ZigTapTunHandle _Nonnull handle);

// ═══════════════════════════════════════════════════════════════════════════
// Packet I/O
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Read packet from device
 * @param handle Device handle
 * @param buffer Buffer to receive packet data
 * @param buffer_size Size of buffer
 * @return Number of bytes read, or negative error code
 */
int32_t zig_taptun_android_read(
    ZigTapTunHandle _Nonnull handle,
    uint8_t* _Nonnull buffer,
    size_t buffer_size
);

/**
 * Write packet to device
 * @param handle Device handle
 * @param data Packet data to write
 * @param length Length of packet
 * @return Error code (Success or error)
 */
ZigTapTunError zig_taptun_android_write(
    ZigTapTunHandle _Nonnull handle,
    const uint8_t* _Nonnull data,
    size_t length
);

// ═══════════════════════════════════════════════════════════════════════════
// Configuration
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Set IPv4 address (for tracking - actual config via VpnService.Builder)
 * @param handle Device handle
 * @param address IPv4 address (network byte order)
 * @param netmask IPv4 netmask (network byte order)
 */
void zig_taptun_android_set_ipv4(
    ZigTapTunHandle _Nonnull handle,
    uint32_t address,
    uint32_t netmask
);

/**
 * Set IPv6 address (for tracking - actual config via VpnService.Builder)
 * @param handle Device handle
 * @param address IPv6 address (16 bytes)
 * @param prefix_len Prefix length (0-128)
 */
void zig_taptun_android_set_ipv6(
    ZigTapTunHandle _Nonnull handle,
    const uint8_t* _Nonnull address,
    uint8_t prefix_len
);

// ═══════════════════════════════════════════════════════════════════════════
// Utilities
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get file descriptor for polling
 * @param handle Device handle
 * @return File descriptor
 */
int32_t zig_taptun_android_get_fd(ZigTapTunHandle _Nonnull handle);

/**
 * Get MTU
 * @param handle Device handle
 * @return MTU value
 */
uint32_t zig_taptun_android_get_mtu(ZigTapTunHandle _Nonnull handle);

/**
 * Get statistics
 * @param handle Device handle
 * @param out_bytes_read Output: total bytes read
 * @param out_bytes_written Output: total bytes written
 * @param out_packets_read Output: total packets read
 * @param out_packets_written Output: total packets written
 */
void zig_taptun_android_get_stats(
    ZigTapTunHandle _Nonnull handle,
    uint64_t* _Nonnull out_bytes_read,
    uint64_t* _Nonnull out_bytes_written,
    uint64_t* _Nonnull out_packets_read,
    uint64_t* _Nonnull out_packets_written
);

// ═══════════════════════════════════════════════════════════════════════════
// JNI Helper Functions
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Convert file descriptor from ParcelFileDescriptor
 * Call this from Java to get the native FD from Android's ParcelFileDescriptor
 * 
 * Java usage:
 * ```java
 * ParcelFileDescriptor pfd = builder.establish();
 * int fd = pfd.getFd();  // This gives you the native FD
 * ```
 */
static inline int32_t zig_taptun_parcel_fd_to_native(JNIEnv* env, jobject parcelFd) {
    if (!parcelFd) return -1;
    
    jclass clazz = (*env)->GetObjectClass(env, parcelFd);
    jmethodID getFdMethod = (*env)->GetMethodID(env, clazz, "getFd", "()I");
    
    if (!getFdMethod) return -1;
    
    return (*env)->CallIntMethod(env, parcelFd, getFdMethod);
}

#ifdef __cplusplus
}
#endif

#endif /* ZIGTAPTUN_ANDROID_H */
