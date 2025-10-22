# ZigTapTun Performance Benchmarks

## Baseline Performance (Oct 23, 2025)

**Platform:** macOS (Apple Silicon)  
**Build:** Debug mode  
**Zig Version:** 0.15.1

### Throughput Benchmark (Ethernet→IP Translation)

**Test Configuration:**
- Packet sizes: 64, 128, 256, 512, 1024, 1400 bytes
- Iterations: 10,000 per size
- Operation: Strip Ethernet header, validate, return IP packet slice

**Results:**
```
Packet Size    Throughput      Packets/sec    Latency
64 bytes       35.00 Mbps      68,367 pps     14.63 µs
128 bytes      86.57 Mbps      84,541 pps     11.83 µs
256 bytes      177.03 Mbps     86,442 pps     11.57 µs
512 bytes      358.49 Mbps     87,522 pps     11.43 µs
1024 bytes     703.86 Mbps     85,921 pps     11.64 µs
1400 bytes     973.04 Mbps     86,879 pps     11.51 µs
```

**Analysis:**
- **Peak throughput:** ~1 Gbps (1400-byte packets)
- **Sustained rate:** ~87K packets/sec across all sizes
- **Average latency:** ~11-12 µs per packet
- **Memory:** Zero leaks ✅

### Latency Benchmark (Ethernet→IP Translation)

**Test Configuration:**
- Packet size: 1,400 bytes (standard MTU)
- Iterations: 10,000
- Operation: Strip Ethernet header, validate, return IP packet slice

**Results:**
```
Min:      4.00 µs
Mean:     5.29 µs
p50:      5.00 µs
p90:      6.00 µs
p99:     16.00 µs
p99.9:   38.00 µs
Max:     77.00 µs
```

**Analysis:**
- Median latency: **5 µs** per packet
- Typical throughput: ~200,000 packets/sec
- 99th percentile under 20 µs (excellent consistency)
- Max latency 77 µs suggests GC/memory allocation overhead

### Next Steps

1. **Fix Remaining Memory Issues** (ZTT-20)
   - ✅ Throughput benchmark fixed
   - ⏳ Latency benchmark needs same fix
   - Document memory ownership rules

2. **Run Release Build**
   - Current numbers are Debug mode
   - Release mode expected 2-3x faster
   - Target: <2 µs median latency, >200K pps sustained

3. **Platform Comparison**
   - Test on Linux (after ZTT-3 validation)
   - Test on Windows (after ZTT-2 completion)
   - Document performance characteristics per platform

4. **Optimize** (Phase 2)
   - Zero-copy path (ZTT-7)
   - SIMD packet validation (ZTT-8)
   - Target: <1 µs latency, 1M+ pps

### Hardware Info

```
macOS (Apple Silicon - M-series)
Zig 0.15.1
```

---

**Notes:**
- These are baseline numbers before optimization
- Memory leaks detected (being fixed in ZTT-20)
- All numbers subject to change with optimizations
- See ROADMAP.md for planned performance improvements
