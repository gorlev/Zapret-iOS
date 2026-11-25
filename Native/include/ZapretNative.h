// C engines linked into the tunnel extension (tools/build-native.sh).
#pragma once
#include <stddef.h>

/// zapret's tpws main(). Blocks while tpws runs; call it once per process.
int tpws_main(int argc, char *argv[]);

/// hev-socks5-tunnel: reads and writes IP packets on tun_fd, sends TCP to a SOCKS5 server.
int hev_socks5_tunnel_main_from_str(const unsigned char *config_str, unsigned int config_len, int tun_fd);
void hev_socks5_tunnel_quit(void);
void hev_socks5_tunnel_stats(size_t *tx_packets, size_t *tx_bytes, size_t *rx_packets, size_t *rx_bytes);
