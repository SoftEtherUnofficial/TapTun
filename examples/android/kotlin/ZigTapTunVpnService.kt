package com.example.zigtaptun

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import kotlin.concurrent.thread

/**
 * VPN Service using ZigTapTun native library
 * 
 * This service integrates with Android's VpnService API and uses
 * the ZigTapTun native library for packet processing.
 */
class ZigTapTunVpnService : VpnService() {

    companion object {
        private const val TAG = "ZigTapTunVPN"
        private const val NOTIFICATION_ID = 1
        private const val NOTIFICATION_CHANNEL_ID = "zigtaptun_vpn"
        
        // Native library loading
        init {
            System.loadLibrary("taptun")
        }
        
        // Native method declarations
        @JvmStatic
        external fun zig_taptun_android_create(fd: Int, mtu: Int): Long
        
        @JvmStatic
        external fun zig_taptun_android_destroy(handle: Long)
        
        @JvmStatic
        external fun zig_taptun_android_read(
            handle: Long,
            buffer: ByteArray,
            bufferSize: Int
        ): Int
        
        @JvmStatic
        external fun zig_taptun_android_write(
            handle: Long,
            data: ByteArray,
            length: Int
        ): Int
        
        @JvmStatic
        external fun zig_taptun_android_set_ipv4(
            handle: Long,
            address: Int,
            netmask: Int
        )
        
        @JvmStatic
        external fun zig_taptun_android_get_fd(handle: Long): Int
        
        @JvmStatic
        external fun zig_taptun_android_get_mtu(handle: Long): Int
    }

    // Service state
    private var vpnInterface: ParcelFileDescriptor? = null
    private var nativeHandle: Long = 0
    private var isRunning = false
    
    // I/O threads
    private var readThread: Thread? = null
    private var writeThread: Thread? = null
    
    // Statistics
    private var bytesRead: Long = 0
    private var bytesWritten: Long = 0
    private var packetsRead: Long = 0
    private var packetsWritten: Long = 0

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "ZigTapTun VPN Service created")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "Starting VPN service")
        
        when (intent?.action) {
            ACTION_START -> startVpn()
            ACTION_STOP -> stopVpn()
        }
        
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "Destroying VPN service")
        stopVpn()
        super.onDestroy()
    }

    private fun startVpn() {
        if (isRunning) {
            Log.w(TAG, "VPN already running")
            return
        }

        try {
            // Configure VPN
            val builder = Builder()
                .setSession("ZigTapTun VPN")
                .setMtu(1500)
                .addAddress("10.0.0.2", 24)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("8.8.8.8")
                .addDnsServer("8.8.4.4")

            // Establish VPN interface
            vpnInterface = builder.establish() ?: run {
                Log.e(TAG, "Failed to establish VPN interface")
                return
            }

            // Get file descriptor
            val fd = vpnInterface!!.fd
            Log.i(TAG, "VPN interface established with FD: $fd")

            // Create native device
            nativeHandle = zig_taptun_android_create(fd, 1500)
            if (nativeHandle == 0L) {
                Log.e(TAG, "Failed to create native device")
                vpnInterface?.close()
                vpnInterface = null
                return
            }

            // Configure native device
            zig_taptun_android_set_ipv4(
                nativeHandle,
                ipToInt("10.0.0.2"),
                ipToInt("255.255.255.0")
            )

            // Start packet processing
            isRunning = true
            startPacketProcessing()

            // Show notification
            startForeground(NOTIFICATION_ID, createNotification())

            Log.i(TAG, "VPN started successfully")

        } catch (e: Exception) {
            Log.e(TAG, "Error starting VPN", e)
            stopVpn()
        }
    }

    private fun stopVpn() {
        Log.i(TAG, "Stopping VPN")
        isRunning = false

        // Stop threads
        readThread?.interrupt()
        writeThread?.interrupt()
        readThread = null
        writeThread = null

        // Destroy native device
        if (nativeHandle != 0L) {
            zig_taptun_android_destroy(nativeHandle)
            nativeHandle = 0
        }

        // Close VPN interface
        vpnInterface?.close()
        vpnInterface = null

        // Stop foreground service
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        Log.i(TAG, "VPN stopped")
    }

    private fun startPacketProcessing() {
        val fd = vpnInterface?.fileDescriptor ?: return
        
        // Input stream (read from TUN, send to native library)
        val inputStream = FileInputStream(fd)
        
        // Output stream (write to TUN from native library)
        val outputStream = FileOutputStream(fd)

        // Read thread: TUN → Native library
        readThread = thread(name = "VPN-Read") {
            val buffer = ByteArray(32768) // 32KB buffer
            
            try {
                while (isRunning && !Thread.interrupted()) {
                    // Read from TUN device
                    val length = inputStream.read(buffer)
                    if (length <= 0) break
                    
                    packetsRead++
                    bytesRead += length
                    
                    // Process packet (in real app, send to translator)
                    // For now, just echo back
                    val result = zig_taptun_android_write(nativeHandle, buffer, length)
                    if (result != 0) {
                        Log.w(TAG, "Write failed: $result")
                    }
                    
                    // Log every 100 packets
                    if (packetsRead % 100L == 0L) {
                        Log.d(TAG, "Read: $packetsRead packets, $bytesRead bytes")
                    }
                }
            } catch (e: Exception) {
                if (isRunning) {
                    Log.e(TAG, "Read thread error", e)
                }
            }
            
            Log.i(TAG, "Read thread stopped")
        }

        // Write thread: Native library → TUN
        writeThread = thread(name = "VPN-Write") {
            val buffer = ByteArray(32768)
            
            try {
                while (isRunning && !Thread.interrupted()) {
                    // Read from native library
                    val length = zig_taptun_android_read(nativeHandle, buffer, buffer.size)
                    
                    when {
                        length > 0 -> {
                            // Write to TUN device
                            outputStream.write(buffer, 0, length)
                            packetsWritten++
                            bytesWritten += length
                            
                            // Log every 100 packets
                            if (packetsWritten % 100L == 0L) {
                                Log.d(TAG, "Write: $packetsWritten packets, $bytesWritten bytes")
                            }
                        }
                        length == -11 -> {
                            // WouldBlock - sleep briefly
                            Thread.sleep(10)
                        }
                        else -> {
                            // Error
                            if (isRunning) {
                                Log.w(TAG, "Read from native failed: $length")
                            }
                            break
                        }
                    }
                }
            } catch (e: Exception) {
                if (isRunning) {
                    Log.e(TAG, "Write thread error", e)
                }
            }
            
            Log.i(TAG, "Write thread stopped")
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("ZigTapTun VPN")
            .setContentText("VPN connection active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "VPN Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "ZigTapTun VPN service status"
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun ipToInt(ip: String): Int {
        val parts = ip.split(".")
        return (parts[0].toInt() shl 24) or
               (parts[1].toInt() shl 16) or
               (parts[2].toInt() shl 8) or
               parts[3].toInt()
    }

    companion object {
        const val ACTION_START = "com.example.zigtaptun.START"
        const val ACTION_STOP = "com.example.zigtaptun.STOP"
    }
}

// Placeholder MainActivity - implement your UI here
class MainActivity : android.app.Activity() {
    // TODO: Implement VPN control UI
}
