# ZigTapTun Android Integration Example

This directory contains example code for integrating ZigTapTun with Android VpnService.

## Overview

Android provides VPN functionality through the **VpnService** API. The system gives you a pre-configured TUN device file descriptor that you can read/write packets from.

**Architecture:**
```
┌─────────────────────────────────────────────┐
│         Android App (APK)                   │
│  - VPN configuration UI                     │
│  - Start/stop service                       │
│  - Connection status display                │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│     VpnService (Background Service)         │
│                                             │
│  ┌─────────────────────────────────────┐  │
│  │  ZigTapTunVpnService (Kotlin)       │  │
│  │  - VpnService.Builder config        │  │
│  │  - File descriptor management       │  │
│  │  - Packet I/O threads               │  │
│  └──────────┬──────────────────────────┘  │
│             │ JNI                          │
│  ┌──────────▼──────────────────────────┐  │
│  │  ZigTapTun Native Library (Zig)     │  │
│  │  - L2L3Translator                   │  │
│  │  - Protocol conversion              │  │
│  │  - Packet processing                │  │
│  └─────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## Files

### Native Code
- **`cpp/zigtaptun_android.h`** - JNI bridge header with C API declarations
- **`cpp/jni_wrapper.cpp`** - JNI wrapper implementation (bridges Java/Kotlin to Zig)
- **`CMakeLists.txt`** - CMake build configuration for multi-ABI builds

### Kotlin/Java Code
- **`kotlin/ZigTapTunVpnService.kt`** - Example VpnService implementation
- **`AndroidManifest.xml`** - Required manifest configuration

### Build Configuration
- **`build.gradle`** - Gradle build configuration (example)
- **`README.md`** - This file

## Requirements

### Development
- Android Studio Arctic Fox or later
- Android NDK r23 or later
- Zig 0.15.1+ for building native library
- Java/Kotlin knowledge

### Runtime
- Android 5.0+ (API 21+)
- Target: Android 14 (API 34)

### Permissions
Your app needs these permissions in `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.BIND_VPN_SERVICE"
    android:permission="android.permission.BIND_VPN_SERVICE" />
```

## Setup Instructions

### 1. Create Android Project

```bash
# Create new Android project in Android Studio
# - Template: "Empty Activity"
# - Language: Kotlin
# - Minimum SDK: API 21 (Android 5.0)
```

### 2. Configure Gradle Build

Add to `app/build.gradle`:

```gradle
android {
    ...
    
    defaultConfig {
        ...
        minSdk 21
        targetSdk 34
        
        ndk {
            abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'
        }
    }
    
    externalNativeBuild {
        cmake {
            path file('src/main/cpp/CMakeLists.txt')
            version '3.18.1'
        }
    }
    
    buildTypes {
        release {
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                          'proguard-rules.pro'
        }
    }
}
```

### 3. Copy Files to Project

```bash
cd YourAndroidProject/app/src/main

# Copy native files
mkdir -p cpp
cp /path/to/ZigTapTun/examples/android/cpp/* cpp/
cp /path/to/ZigTapTun/examples/android/CMakeLists.txt cpp/

# Copy Kotlin files
mkdir -p kotlin/com/example/zigtaptun
cp /path/to/ZigTapTun/examples/android/kotlin/* kotlin/com/example/zigtaptun/
```

### 4. Configure AndroidManifest.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.zigtaptun">

    <!-- Required permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:theme="@style/AppTheme">

        <!-- Main Activity -->
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- VPN Service -->
        <service
            android:name=".ZigTapTunVpnService"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
    </application>
</manifest>
```

### 5. Build Native Library

The CMake configuration will automatically build the Zig library during Android build.

**Manual build (for testing):**
```bash
cd /path/to/ZigTapTun

# Build for each Android ABI
zig build -Dtarget=aarch64-linux-android -Drelease=true
zig build -Dtarget=armv7a-linux-androideabi -Drelease=true
zig build -Dtarget=x86_64-linux-android -Drelease=true
zig build -Dtarget=i386-linux-android -Drelease=true
```

### 6. Build and Run

1. **Sync Gradle:**
   - File → Sync Project with Gradle Files

2. **Build APK:**
   - Build → Make Project
   - Build → Build Bundle(s) / APK(s) → Build APK(s)

3. **Install on Device:**
   - Connect Android device via USB
   - Enable USB debugging
   - Run → Run 'app'

4. **Grant VPN Permission:**
   - App will request VPN permission on first start
   - Grant permission in dialog

## Usage Example

### Request VPN Permission

```kotlin
class MainActivity : AppCompatActivity() {
    companion object {
        private const val VPN_REQUEST_CODE = 1
    }
    
    private fun prepareVpn() {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            // Need to request permission
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            // Permission already granted
            startVpn()
        }
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE && resultCode == RESULT_OK) {
            startVpn()
        }
    }
    
    private fun startVpn() {
        val intent = Intent(this, ZigTapTunVpnService::class.java).apply {
            action = ZigTapTunVpnService.ACTION_START
        }
        startService(intent)
    }
    
    private fun stopVpn() {
        val intent = Intent(this, ZigTapTunVpnService::class.java).apply {
            action = ZigTapTunVpnService.ACTION_STOP
        }
        startService(intent)
    }
}
```

## Architecture Details

### File Descriptor Flow

1. **VpnService.Builder.establish()** creates TUN device and returns `ParcelFileDescriptor`
2. **Get native FD:** `pfd.fd` gives you the integer file descriptor
3. **Pass to native:** `zig_taptun_android_create(fd, mtu)`
4. **Read/write packets:** Use standard file I/O or native functions

### Thread Model

```
Main Thread (Service)
├─ VPN configuration
├─ Service lifecycle
│
├─ Read Thread
│  ├─ FileInputStream.read() → TUN device
│  └─ zig_taptun_android_write() → Native processing
│
└─ Write Thread
   ├─ zig_taptun_android_read() → Native processing
   └─ FileOutputStream.write() → TUN device
```

### Memory Management

- **Packet Buffers:** Reuse ByteArray buffers (typical size: 32KB)
- **JNI Overhead:** Minimal - direct byte array access
- **Native Memory:** Managed by Zig allocator
- **No GC Pressure:** Avoid allocations in hot path

## Performance Tips

1. **Buffer Sizes:**
   - Use 32KB buffers for efficient bulk transfers
   - Don't allocate per-packet

2. **Batch Processing:**
   - Process multiple packets before context switch
   - Reduces thread overhead

3. **Thread Priority:**
   ```kotlin
   thread(name = "VPN-Read", priority = Thread.MAX_PRIORITY) {
       // High priority for packet processing
   }
   ```

4. **Wake Locks:**
   - Acquire partial wake lock to prevent sleep during active transfer
   - Release when idle

5. **Battery Optimization:**
   - Use `doze` mode appropriately
   - Reduce polling when idle
   - Monitor data transfer rates

## Testing

### ADB Commands

```bash
# View VPN interfaces
adb shell ip addr show

# View routes
adb shell ip route

# Monitor logs
adb logcat -s ZigTapTunVPN:*

# Check VPN status
adb shell dumpsys connectivity
```

### Packet Capture

```bash
# Capture packets (requires root)
adb shell tcpdump -i any -w /sdcard/capture.pcap

# Pull capture file
adb pull /sdcard/capture.pcap
```

### Performance Testing

```bash
# Network speed test
adb shell am start -n com.netflix.Speedtest/.MainActivity

# CPU usage
adb shell top -m 10

# Memory usage
adb shell dumpsys meminfo com.example.zigtaptun
```

## Troubleshooting

### VPN Won't Start
- Check permissions in AndroidManifest.xml
- Verify BIND_VPN_SERVICE permission
- Check logcat for errors
- Ensure native library loaded correctly

### Packets Not Flowing
- Verify file descriptor is valid
- Check read/write threads are running
- Monitor logcat for native errors
- Test with simple echo (packet loopback)

### Crashes
```bash
# Get crash logs
adb logcat -b crash

# Native crash symbols
ndk-stack -sym app/build/intermediates/cmake/debug/obj/arm64-v8a

# Memory leaks
adb shell dumpsys meminfo --package com.example.zigtaptun
```

### Build Errors
```bash
# Clean build
./gradlew clean

# Rebuild native
./gradlew externalNativeBuildDebug

# Check Zig is in PATH
which zig

# CMake debug output
./gradlew --debug externalNativeBuildDebug
```

## Production Checklist

- [ ] Configure proper app signing
- [ ] Add connection encryption (TLS/SSL)
- [ ] Implement reconnection logic
- [ ] Add split tunneling support
- [ ] Handle airplane mode transitions
- [ ] Battery optimization (doze mode)
- [ ] Data usage statistics
- [ ] Connection status notifications
- [ ] Error reporting/analytics
- [ ] Test on various Android versions (5.0 - 14)
- [ ] Test on different devices (Samsung, Pixel, etc.)
- [ ] ProGuard/R8 configuration for release
- [ ] Play Store compliance (data policy, etc.)

## Resources

### Android Documentation
- [VpnService](https://developer.android.com/reference/android/net/VpnService)
- [VpnService.Builder](https://developer.android.com/reference/android/net/VpnService.Builder)
- [NDK Guide](https://developer.android.com/ndk/guides)

### Sample Projects
- [Android ToyVpn Sample](https://github.com/android/connectivity-samples/tree/main/ToyVpn)

### Tools
- [Wireshark](https://www.wireshark.org/) - Packet analysis
- [Android Profiler](https://developer.android.com/studio/profile/android-profiler) - Performance

## Support

- **Issues:** https://github.com/SoftEtherUnofficial/ZigTapTun/issues
- **Discussions:** https://github.com/SoftEtherUnofficial/ZigTapTun/discussions
- **YouTrack:** https://youtrack.devstroop.com/project/ZTT

## License

See main project LICENSE file.
