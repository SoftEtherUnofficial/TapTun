//
//  jni_wrapper.cpp
//  JNI Wrapper for ZigTapTun Android Integration
//
//  This file bridges Java/Kotlin code to the ZigTapTun native library.
//  It implements JNI methods that match the declarations in ZigTapTunVpnService.kt
//

#include <jni.h>
#include <android/log.h>
#include <string.h>
#include <errno.h>
#include "zigtaptun_android.h"

// Logging macros
#define LOG_TAG "ZigTapTun-JNI"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ═══════════════════════════════════════════════════════════════════════════
// Helper Functions
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Validate handle pointer
 */
static inline bool validate_handle(ZigTapTunHandle handle) {
    if (!handle) {
        LOGE("Invalid handle: NULL");
        return false;
    }
    return true;
}

/**
 * Convert error code to string
 */
static const char* error_to_string(ZigTapTunError error) {
    switch (error) {
        case ZigTapTunError_Success: return "Success";
        case ZigTapTunError_OutOfMemory: return "Out of memory";
        case ZigTapTunError_InvalidParameter: return "Invalid parameter";
        case ZigTapTunError_InvalidFileDescriptor: return "Invalid file descriptor";
        case ZigTapTunError_DeviceNotActive: return "Device not active";
        case ZigTapTunError_DeviceClosed: return "Device closed";
        case ZigTapTunError_BufferTooSmall: return "Buffer too small";
        case ZigTapTunError_PacketTooLarge: return "Packet too large";
        case ZigTapTunError_ReadFailed: return "Read failed";
        case ZigTapTunError_WriteFailed: return "Write failed";
        case ZigTapTunError_PartialWrite: return "Partial write";
        case ZigTapTunError_WouldBlock: return "Would block";
        case ZigTapTunError_Unknown: return "Unknown error";
        default: return "Undefined error";
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// JNI Method Implementations
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Create Android VPN device from file descriptor
 * 
 * Java signature:
 * native static long zig_taptun_android_create(int fd, int mtu);
 */
extern "C" JNIEXPORT jlong JNICALL
Java_com_example_zigtaptun_ZigTapTunVpnService_zig_1taptun_1android_1create(
    JNIEnv* env,
    jclass clazz,
    jint fd,
    jint mtu
) {
    LOGI("Creating Android VPN device: fd=%d, mtu=%d", fd, mtu);
    
    // Validate parameters
    if (fd < 0) {
        LOGE("Invalid file descriptor: %d", fd);
        return 0;
    }
    
    if (mtu <= 0 || mtu > 65535) {
        LOGE("Invalid MTU: %d", mtu);
        return 0;
    }
    
    // Create device
    ZigTapTunHandle handle = zig_taptun_android_create(fd, static_cast<uint32_t>(mtu));
    
    if (!handle) {
        LOGE("Failed to create Android VPN device");
        return 0;
    }
    
    LOGI("Successfully created device: handle=%p", handle);
    return reinterpret_cast<jlong>(handle);
}

/**
 * Destroy Android VPN device
 * 
 * Java signature:
 * native static void zig_taptun_android_destroy(long handle);
 */
extern "C" JNIEXPORT void JNICALL
Java_com_example_zigtaptun_ZigTapTunVpnService_zig_1taptun_1android_1destroy(
    JNIEnv* env,
    jclass clazz,
    jlong handle
) {
    LOGD("Destroying device: handle=%p", reinterpret_cast<void*>(handle));
    
    ZigTapTunHandle dev_handle = reinterpret_cast<ZigTapTunHandle>(handle);
    if (!validate_handle(dev_handle)) {
        return;
    }
    
    zig_taptun_android_destroy(dev_handle);
    LOGI("Device destroyed successfully");
}

/**
 * Read packet from device
 * 
 * Java signature:
 * native static int zig_taptun_android_read(long handle, byte[] buffer, int bufferSize);
 */
extern "C" JNIEXPORT jint JNICALL
Java_com_example_zigtaptun_ZigTapTunVpnService_zig_1taptun_1android_1read(
    JNIEnv* env,
    jclass clazz,
    jlong handle,
    jbyteArray buffer,
    jint buffer_size
) {
    ZigTapTunHandle dev_handle = reinterpret_cast<ZigTapTunHandle>(handle);
    if (!validate_handle(dev_handle)) {
        return ZigTapTunError_InvalidParameter;
    }
    
    // Validate buffer
    if (!buffer) {
        LOGE("Buffer is NULL");
        return ZigTapTunError_InvalidParameter;
    }
    
    // Check buffer size
    jsize java_buffer_size = env->GetArrayLength(buffer);
    if (buffer_size > java_buffer_size) {
        LOGE("Requested buffer size (%d) exceeds array length (%d)", buffer_size, java_buffer_size);
        return ZigTapTunError_BufferTooSmall;
    }
    
    // Get direct pointer to Java array
    jbyte* buffer_ptr = env->GetByteArrayElements(buffer, nullptr);
    if (!buffer_ptr) {
        LOGE("Failed to get buffer pointer");
        return ZigTapTunError_OutOfMemory;
    }
    
    // Read from device
    int32_t result = zig_taptun_android_read(
        dev_handle,
        reinterpret_cast<uint8_t*>(buffer_ptr),
        static_cast<size_t>(buffer_size)
    );
    
    // Release array (copy back modified data)
    env->ReleaseByteArrayElements(buffer, buffer_ptr, 0);
    
    if (result < 0 && result != ZigTapTunError_WouldBlock) {
        LOGW("Read error: %d (%s)", result, error_to_string(static_cast<ZigTapTunError>(result)));
    }
    
    return result;
}

/**
 * Write packet to device
 * 
 * Java signature:
 * native static int zig_taptun_android_write(long handle, byte[] data, int length);
 */
extern "C" JNIEXPORT jint JNICALL
Java_com_example_zigtaptun_ZigTapTunVpnService_zig_1taptun_1android_1write(
    JNIEnv* env,
    jclass clazz,
    jlong handle,
    jbyteArray data,
    jint length
) {
    ZigTapTunHandle dev_handle = reinterpret_cast<ZigTapTunHandle>(handle);
    if (!validate_handle(dev_handle)) {
        return ZigTapTunError_InvalidParameter;
    }
    
    // Validate data
    if (!data) {
        LOGE("Data buffer is NULL");
        return ZigTapTunError_InvalidParameter;
    }
    
    // Check length
    jsize java_array_size = env->GetArrayLength(data);
    if (length > java_array_size) {
        LOGE("Requested length (%d) exceeds array size (%d)", length, java_array_size);
        return ZigTapTunError_InvalidParameter;
    }
    
    if (length <= 0) {
        LOGE("Invalid length: %d", length);
        return ZigTapTunError_InvalidParameter;
    }
    
    // Get direct pointer to Java array
    jbyte* data_ptr = env->GetByteArrayElements(data, nullptr);
    if (!data_ptr) {
        LOGE("Failed to get data pointer");
        return ZigTapTunError_OutOfMemory;
    }
    
    // Write to device
    ZigTapTunError result = zig_taptun_android_write(
        dev_handle,
        reinterpret_cast<const uint8_t*>(data_ptr),
        static_cast<size_t>(length)
    );
    
    // Release array (no need to copy back - read-only)
    env->ReleaseByteArrayElements(data, data_ptr, JNI_ABORT);
    
    if (result != ZigTapTunError_Success) {
        LOGW("Write error: %d (%s)", result, error_to_string(result));
    }
    
    return result;
}

/**
 * Set IPv4 address (tracking only - actual config via VpnService.Builder)
 * 
 * Java signature:
 * native static void zig_taptun_android_set_ipv4(long handle, int address, int netmask);
 */
extern "C" JNIEXPORT void JNICALL
Java_com_example_zigtaptun_ZigTapTunVpnService_zig_1taptun_1android_1set_1ipv4(
    JNIEnv* env,
    jclass clazz,
    jlong handle,
    jint address,
    jint netmask
) {
    ZigTapTunHandle dev_handle = reinterpret_cast<ZigTapTunHandle>(handle);
    if (!validate_handle(dev_handle)) {
        return;
    }
    
    LOGD("Setting IPv4: address=0x%08x, netmask=0x%08x", address, netmask);
    
    zig_taptun_android_set_ipv4(
        dev_handle,
        static_cast<uint32_t>(address),
        static_cast<uint32_t>(netmask)
    );
}

/**
 * Get file descriptor for polling
 * 
 * Java signature:
 * native static int zig_taptun_android_get_fd(long handle);
 */
extern "C" JNIEXPORT jint JNICALL
Java_com_example_zigtaptun_ZigTapTunVpnService_zig_1taptun_1android_1get_1fd(
    JNIEnv* env,
    jclass clazz,
    jlong handle
) {
    ZigTapTunHandle dev_handle = reinterpret_cast<ZigTapTunHandle>(handle);
    if (!validate_handle(dev_handle)) {
        return -1;
    }
    
    int32_t fd = zig_taptun_android_get_fd(dev_handle);
    LOGD("Get FD: handle=%p, fd=%d", dev_handle, fd);
    
    return fd;
}

/**
 * Get MTU
 * 
 * Java signature:
 * native static int zig_taptun_android_get_mtu(long handle);
 */
extern "C" JNIEXPORT jint JNICALL
Java_com_example_zigtaptun_ZigTapTunVpnService_zig_1taptun_1android_1get_1mtu(
    JNIEnv* env,
    jclass clazz,
    jlong handle
) {
    ZigTapTunHandle dev_handle = reinterpret_cast<ZigTapTunHandle>(handle);
    if (!validate_handle(dev_handle)) {
        return 0;
    }
    
    uint32_t mtu = zig_taptun_android_get_mtu(dev_handle);
    LOGD("Get MTU: handle=%p, mtu=%u", dev_handle, mtu);
    
    return static_cast<jint>(mtu);
}

// ═══════════════════════════════════════════════════════════════════════════
// JNI_OnLoad - Called when library is loaded
// ═══════════════════════════════════════════════════════════════════════════

/**
 * JNI_OnLoad is called when the library is loaded by System.loadLibrary()
 * This is the perfect place to perform initialization and cache JNI references.
 */
extern "C" JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM* vm, void* reserved) {
    LOGI("ZigTapTun JNI library loaded");
    LOGI("JNI version: 0x%08x", JNI_VERSION_1_6);
    
    JNIEnv* env;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        LOGE("Failed to get JNIEnv");
        return JNI_ERR;
    }
    
    // Verify that our native methods can be found
    // This helps catch signature mismatches early
    jclass vpnServiceClass = env->FindClass("com/example/zigtaptun/ZigTapTunVpnService");
    if (!vpnServiceClass) {
        LOGE("Failed to find ZigTapTunVpnService class");
        return JNI_ERR;
    }
    
    LOGI("Successfully loaded ZigTapTun JNI library");
    return JNI_VERSION_1_6;
}

/**
 * JNI_OnUnload - Called when library is unloaded
 */
extern "C" JNIEXPORT void JNICALL
JNI_OnUnload(JavaVM* vm, void* reserved) {
    LOGI("ZigTapTun JNI library unloaded");
}
