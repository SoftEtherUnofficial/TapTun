#ifndef TAPTUN_FFI_H
#define TAPTUN_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque handle to TapTun L2L3 Translator
 */
typedef struct TapTunTranslator TapTunTranslator;

/**
 * Create a new L2L3 translator instance
 * 
 * @param our_mac 6-byte MAC address for this virtual interface
 * @return Opaque translator handle, or NULL on failure
 */
TapTunTranslator* taptun_translator_create(const uint8_t* our_mac);

/**
 * Destroy translator and free all resources
 * 
 * @param handle Translator handle from taptun_translator_create()
 */
void taptun_translator_destroy(TapTunTranslator* handle);

/**
 * Convert Ethernet frame (L2) to IP packet (L3)
 * 
 * Strips Ethernet header, handles ARP internally, extracts IP payload.
 * 
 * @param handle Translator handle
 * @param eth_frame Input Ethernet frame buffer
 * @param frame_len Length of Ethernet frame
 * @param out_ip_packet Output buffer for IP packet
 * @param out_buffer_size Size of output buffer
 * @return Length of IP packet (>0), 0 if handled internally (ARP), 
 *         -1 on error, -2 if buffer too small
 */
int taptun_ethernet_to_ip(
    TapTunTranslator* handle,
    const uint8_t* eth_frame,
    size_t frame_len,
    uint8_t* out_ip_packet,
    size_t out_buffer_size
);

/**
 * Convert IP packet (L3) to Ethernet frame (L2)
 * 
 * Adds Ethernet header with learned gateway MAC, prepares for L2 transmission.
 * 
 * @param handle Translator handle
 * @param ip_packet Input IP packet buffer
 * @param packet_len Length of IP packet
 * @param out_eth_frame Output buffer for Ethernet frame
 * @param out_buffer_size Size of output buffer
 * @return Length of Ethernet frame (>0), -1 on error, -2 if buffer too small
 */
int taptun_ip_to_ethernet(
    TapTunTranslator* handle,
    const uint8_t* ip_packet,
    size_t packet_len,
    uint8_t* out_eth_frame,
    size_t out_buffer_size
);

/**
 * Get translator statistics
 * 
 * @param handle Translator handle
 * @param out_l2_to_l3 Pointer to receive L2→L3 packet count (can be NULL)
 * @param out_l3_to_l2 Pointer to receive L3→L2 packet count (can be NULL)
 * @param out_arp_handled Pointer to receive ARP requests handled count (can be NULL)
 */
void taptun_translator_stats(
    TapTunTranslator* handle,
    uint64_t* out_l2_to_l3,
    uint64_t* out_l3_to_l2,
    uint64_t* out_arp_handled
);

/**
 * Check if gateway MAC address has been learned
 * 
 * @param handle Translator handle
 * @return 1 if gateway MAC learned, 0 otherwise
 */
int taptun_translator_has_gateway_mac(TapTunTranslator* handle);

/**
 * Get learned gateway MAC address
 * 
 * @param handle Translator handle
 * @param out_mac 6-byte buffer to receive MAC address
 * @return 1 if MAC was learned and copied, 0 if not learned
 */
int taptun_translator_get_gateway_mac(
    TapTunTranslator* handle,
    uint8_t* out_mac
);

/**
 * Check if there are pending ARP replies to send
 * 
 * When handle_arp is enabled, TapTun generates ARP replies internally.
 * This function checks if any replies are queued and ready to send.
 * 
 * @param handle Translator handle
 * @return 1 if ARP replies available, 0 if not
 */
int taptun_translator_has_arp_reply(TapTunTranslator* handle);

/**
 * Get next queued ARP reply (complete Ethernet frame)
 * 
 * Retrieves and removes the next ARP reply from the queue.
 * The returned frame is a complete Ethernet frame (typically 42-60 bytes)
 * ready to send back to the server.
 * 
 * @param handle Translator handle
 * @param out_frame Output buffer for Ethernet frame
 * @param out_buffer_size Size of output buffer
 * @return Length of Ethernet frame (>0), 0 if no replies available,
 *         -1 on error, -2 if buffer too small
 */
int taptun_translator_pop_arp_reply(
    TapTunTranslator* handle,
    uint8_t* out_frame,
    size_t out_buffer_size
);

/**
 * Manually set our IP address
 * 
 * Required for ARP reply generation. When handle_arp is enabled,
 * TapTun needs to know our IP address to respond to ARP requests.
 * Call this after receiving DHCP configuration.
 * 
 * @param handle Translator handle
 * @param ip IP address in network byte order (big endian)
 */
void taptun_translator_set_our_ip(
    TapTunTranslator* handle,
    uint32_t ip
);

/**
 * Manually set gateway IP address
 * 
 * @param handle Translator handle
 * @param gateway_ip Gateway IP address in network byte order (big endian)
 */
void taptun_translator_set_gateway_ip(
    TapTunTranslator* handle,
    uint32_t gateway_ip
);

#ifdef __cplusplus
}
#endif

#endif /* TAPTUN_FFI_H */
