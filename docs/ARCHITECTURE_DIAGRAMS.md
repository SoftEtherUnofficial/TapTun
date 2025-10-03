# ZigTapTun Architecture Diagrams

## High-Level Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     Application Layer                          │
│                                                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ VPN Client   │  │   Router     │  │   Bridge     │       │
│  │ (SoftEther)  │  │              │  │              │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                 │                │
└─────────┼─────────────────┼─────────────────┼────────────────┘
          │                 │                 │
┌─────────┼─────────────────┼─────────────────┼────────────────┐
│         │   ZigTapTun API │                 │                │
│         ▼                 ▼                 ▼                │
│  ┌────────────────────────────────────────────────┐          │
│  │              Device Interface                  │          │
│  │  • open() • close() • read() • write()        │          │
│  └────────────────────────────────────────────────┘          │
│                                                               │
│  ┌─────────────────┐              ┌─────────────────┐        │
│  │   TunDevice     │              │   TapDevice     │        │
│  │   (Layer 3)     │              │   (Layer 2)     │        │
│  │                 │              │                 │        │
│  │ • Raw IP pkts   │              │ • Ethernet frms │        │
│  │ • No broadcast  │              │ • Full L2       │        │
│  │ • Point-to-pt   │              │ • Bridge mode   │        │
│  └────────┬────────┘              └────────┬────────┘        │
│           │                                │                 │
│           └────────────┬───────────────────┘                 │
│                        │                                     │
│              ┌─────────▼──────────┐                          │
│              │  L2L3Translator    │                          │
│              │                    │                          │
│              │  • IP ↔ Ethernet   │                          │
│              │  • ARP handling    │                          │
│              │  • MAC learning    │                          │
│              │  • IP learning     │                          │
│              └─────────┬──────────┘                          │
│                        │                                     │
└────────────────────────┼─────────────────────────────────────┘
                         │
┌────────────────────────┼─────────────────────────────────────┐
│         Platform Layer │                                     │
│                        ▼                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │  macOS   │  │  Linux   │  │ Windows  │  │ FreeBSD  │    │
│  │  utun    │  │ /dev/tun │  │ TAP-Win  │  │ /dev/tun │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
└────────────────────────────────────────────────────────────────┘
```

## L2↔L3 Translation Flow

### Outgoing: TUN → Network (L3 → L2)

```
  macOS Kernel                ZigTapTun              Network/VPN
┌──────────────┐           ┌─────────────┐         ┌──────────────┐
│              │           │             │         │              │
│ [App writes  │           │             │         │              │
│  to socket]  │           │             │         │              │
│      │       │           │             │         │              │
│      ▼       │           │             │         │              │
│  ┌────────┐  │           │             │         │              │
│  │Routing │  │           │             │         │              │
│  │ Table  │  │           │             │         │              │
│  └────┬───┘  │           │             │         │              │
│       │      │           │             │         │              │
│       ▼      │           │             │         │              │
│  ┌────────┐  │           │             │         │              │
│  │ utun8  │  │           │             │         │              │
│  │ device │  │  read()   │             │         │              │
│  └────┬───┘  ├──────────►│ IP Packet   │         │              │
│       │      │           │ 84 bytes    │         │              │
│       │      │           │             │         │              │
│  Raw IP pkt  │           │ ┌─────────┐ │         │              │
│  (no Ether   │           │ │IP Learn │ │         │              │
│   header)    │           │ │ Module  │ │         │              │
│              │           │ └────┬────┘ │         │              │
│              │           │      │      │         │              │
│              │           │   Learn:    │         │              │
│              │           │  10.21.255. │         │              │
│              │           │    .100     │         │              │
│              │           │      │      │         │              │
│              │           │      ▼      │         │              │
│              │           │ ┌─────────┐ │         │              │
│              │           │ │ L3→L2   │ │         │              │
│              │           │ │Translate│ │         │              │
│              │           │ └────┬────┘ │         │              │
│              │           │      │      │         │              │
│              │           │   Add 14B   │         │              │
│              │           │   Ethernet  │         │              │
│              │           │   header:   │         │              │
│              │           │             │         │              │
│              │           │  FF:FF:... ─┐         │              │
│              │           │  02:00:5E.. │         │              │
│              │           │  0x0800     │         │              │
│              │           │  [IP pkt]   │         │              │
│              │           │      │      │         │              │
│              │           │      ▼      │         │              │
│              │           │ Ethernet    │  send() │              │
│              │           │ Frame       ├────────►│ SoftEther    │
│              │           │ 98 bytes    │         │ Session      │
│              │           │             │         │              │
└──────────────┘           └─────────────┘         └──────────────┘
```

### Incoming: Network → TUN (L2 → L3)

```
  Network/VPN              ZigTapTun                macOS Kernel
┌──────────────┐         ┌─────────────┐         ┌──────────────┐
│              │         │             │         │              │
│ SoftEther    │ recv()  │             │         │              │
│ Server       ├────────►│ Ethernet    │         │              │
│              │         │ Frame       │         │              │
│ Sends:       │         │ 60 bytes    │         │              │
│              │         │             │         │              │
│ ARP Request  │         │ ┌─────────┐ │         │              │
│ "Who has     │         │ │EtherType│ │         │              │
│ 10.21.255.   │         │ │ Check   │ │         │              │
│  100?"       │         │ └────┬────┘ │         │              │
│              │         │      │      │         │              │
│              │         │   0x0806    │         │              │
│              │         │   (ARP)     │         │              │
│              │         │      │      │         │              │
│              │         │      ▼      │         │              │
│              │         │ ┌─────────┐ │         │              │
│              │         │ │   ARP   │ │         │              │
│              │         │ │ Handler │ │         │              │
│              │         │ └────┬────┘ │         │              │
│              │         │      │      │         │              │
│              │         │   Request   │         │              │
│              │         │   for our   │         │              │
│              │         │   IP? YES   │         │              │
│              │         │      │      │         │              │
│              │         │      ▼      │         │              │
│              │         │ Build ARP   │         │              │
│              │         │ Reply:      │         │              │
│              │         │             │         │              │
│              │         │ Target:     │         │              │
│              │         │  82:5c:...  │         │              │
│              │         │ Sender:     │         │              │
│              │         │  02:00:5E.. │         │              │
│              │         │ Sender IP:  │         │              │
│              │         │  10.21.255. │         │              │
│              │ send()  │    .100     │         │              │
│ ◄───────────┤         │             │         │              │
│ ARP Reply    │         │ (42 bytes)  │         │              │
│              │         │             │         │              │
│ Later...     │         │             │         │              │
│              │         │             │         │              │
│ ICMP Echo    │ recv()  │             │         │              │
│ Reply        ├────────►│ Ethernet    │         │              │
│              │         │ Frame       │         │              │
│              │         │ 98 bytes    │         │              │
│              │         │             │         │              │
│              │         │ ┌─────────┐ │         │              │
│              │         │ │EtherType│ │         │              │
│              │         │ │ 0x0800  │ │         │              │
│              │         │ │ (IPv4)  │ │         │              │
│              │         │ └────┬────┘ │         │              │
│              │         │      │      │         │              │
│              │         │   Strip     │         │              │
│              │         │   14B Ether │         │              │
│              │         │   header    │         │              │
│              │         │      │      │         │              │
│              │         │      ▼      │         │              │
│              │         │ IP Packet   │ write() │              │
│              │         │ 84 bytes    ├────────►│ utun8        │
│              │         │             │         │ device       │
│              │         │             │         │     │        │
│              │         │             │         │     ▼        │
│              │         │             │         │ [App recv    │
│              │         │             │         │  from socket]│
│              │         │             │         │              │
└──────────────┘         └─────────────┘         └──────────────┘
```

## Packet Structure Comparison

### TUN Device (Layer 3)
```
┌────────────────────────────────────────┐
│          4-byte AF header              │  ← macOS/BSD only
│         (AF_INET or AF_INET6)          │
├────────────────────────────────────────┤
│                                        │
│           IP Packet (20+ bytes)        │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │ Version | IHL | TOS | Total Len │  │
│  ├──────────────────────────────────┤  │
│  │     ID      | Flags | Frag Off  │  │
│  ├──────────────────────────────────┤  │
│  │  TTL  | Proto |   Checksum      │  │
│  ├──────────────────────────────────┤  │
│  │        Source IP Address         │  │
│  ├──────────────────────────────────┤  │
│  │      Destination IP Address      │  │
│  ├──────────────────────────────────┤  │
│  │      Options (if any)            │  │
│  ├──────────────────────────────────┤  │
│  │         Payload (ICMP,           │  │
│  │         TCP, UDP, etc.)          │  │
│  └──────────────────────────────────┘  │
│                                        │
└────────────────────────────────────────┘
    ↑
    NO Ethernet header!
    NO destination MAC!
    NO source MAC!
    NO EtherType!
```

### TAP Device / Ethernet Frame (Layer 2)
```
┌────────────────────────────────────────┐
│    Ethernet Header (14 bytes)          │
│  ┌──────────────────────────────────┐  │
│  │   Destination MAC (6 bytes)      │  │  ← Who to send to
│  │   FF:FF:FF:FF:FF:FF (broadcast)  │  │
│  │   or specific MAC address        │  │
│  ├──────────────────────────────────┤  │
│  │   Source MAC (6 bytes)           │  │  ← Who sent it
│  │   02:00:5E:xx:xx:xx              │  │
│  ├──────────────────────────────────┤  │
│  │   EtherType (2 bytes)            │  │  ← What's inside
│  │   0x0800 = IPv4                  │  │
│  │   0x0806 = ARP                   │  │
│  │   0x86DD = IPv6                  │  │
│  └──────────────────────────────────┘  │
├────────────────────────────────────────┤
│         Payload (46-1500 bytes)        │
│                                        │
│  For IPv4 (EtherType 0x0800):         │
│  ┌──────────────────────────────────┐  │
│  │      IP Packet (same as TUN)     │  │
│  └──────────────────────────────────┘  │
│                                        │
│  For ARP (EtherType 0x0806):          │
│  ┌──────────────────────────────────┐  │
│  │  HW Type | Proto Type | Sizes    │  │
│  │  Opcode (1=Req, 2=Reply)         │  │
│  │  Sender MAC | Sender IP          │  │
│  │  Target MAC | Target IP          │  │
│  └──────────────────────────────────┘  │
│                                        │
└────────────────────────────────────────┘
```

## MAC Address Learning Flow

```
Time →

t=0: Connection established
     ┌─────────────────────────────┐
     │ g_our_ip = NULL             │
     │ g_gateway_mac = NULL        │
     └─────────────────────────────┘

t=1: First ping sent (10.21.255.100 → 10.21.0.1)
     ┌─────────────────────────────┐
     │ Read from TUN: IP packet    │
     │ Source IP: 10.21.255.100    │
     │         ↓                   │
     │ [IP Learning Module]        │
     │         ↓                   │
     │ g_our_ip = 0x0A15FF64 ✅    │
     │                             │
     │ Add Ethernet header:        │
     │ Dest: FF:FF:FF:FF:FF:FF     │ ← Broadcast (gateway MAC unknown)
     │ Src:  02:00:5E:xx:xx:xx     │
     └─────────────────────────────┘

t=2: Gateway sends ARP request
     ┌─────────────────────────────┐
     │ Recv from VPN: ARP packet   │
     │ Opcode: 1 (Request)         │
     │ "Who has 10.21.255.100?"    │
     │         ↓                   │
     │ [ARP Handler]               │
     │         ↓                   │
     │ Send ARP Reply:             │
     │ "I have 10.21.255.100"      │
     │ "My MAC: 02:00:5E:xx:xx:xx" │
     └─────────────────────────────┘

t=3: Gateway sends ARP reply (optional)
     ┌─────────────────────────────┐
     │ Recv from VPN: ARP packet   │
     │ Opcode: 2 (Reply)           │
     │ Sender IP: 10.21.0.1        │
     │ Sender MAC: 82:5c:48:46:... │
     │         ↓                   │
     │ [MAC Learning Module]       │
     │         ↓                   │
     │ g_gateway_mac = 0x825c... ✅│
     └─────────────────────────────┘

t=4: Subsequent pings
     ┌─────────────────────────────┐
     │ Add Ethernet header:        │
     │ Dest: 82:5c:48:46:b6:a2 ✅  │ ← Direct to gateway
     │ Src:  02:00:5E:xx:xx:xx     │
     │         ↓                   │
     │ Lower latency!              │
     │ No broadcast needed!        │
     └─────────────────────────────┘
```

## State Machine

```
             ┌──────────────────┐
             │  DISCONNECTED    │
             └────────┬─────────┘
                      │
                  connect()
                      │
                      ▼
             ┌──────────────────┐
             │   INITIALIZING   │
             │  • Open TUN      │
             │  • Generate MAC  │
             └────────┬─────────┘
                      │
                   success
                      │
                      ▼
             ┌──────────────────┐
             │   IP_UNKNOWN     │
             │  • Waiting for   │
             │    first packet  │
             └────────┬─────────┘
                      │
              outgoing IP packet
                      │
                      ▼
             ┌──────────────────┐
             │   IP_LEARNED     │──────┐ ARP request
             │  • Know our IP   │      │ received
             │  • Gateway MAC   │◄─────┘ Send ARP reply
             │    unknown       │
             └────────┬─────────┘
                      │
            ARP reply from gateway
                      │
                      ▼
             ┌──────────────────┐
             │  FULLY_LEARNED   │
             │  • Know our IP   │
             │  • Know gateway  │
             │    MAC address   │
             │  • Optimal path  │
             └────────┬─────────┘
                      │
                  disconnect()
                      │
                      ▼
             ┌──────────────────┐
             │   DISCONNECTED   │
             └──────────────────┘
```

This visual documentation helps understand:
1. How packets flow through the system
2. The difference between L2 (TAP) and L3 (TUN)
3. How MAC and IP learning work
4. The complete state machine
