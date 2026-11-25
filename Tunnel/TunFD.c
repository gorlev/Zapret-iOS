// Finds the utun socket that NetworkExtension opened for this extension, so
// hev-socks5-tunnel can read and write packets on it directly. The iOS SDK
// leaves out <sys/kern_control.h>, so the few definitions it needs are here.
#include "TunFD.h"
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>

#ifndef AF_SYSTEM
#define AF_SYSTEM 32
#endif
#define ZAPRET_CTLIOCGINFO 0xc0644e03UL

struct zapret_ctl_info { u_int32_t ctl_id; char ctl_name[96]; };
struct zapret_sockaddr_ctl {
    u_char sc_len; u_char sc_family; u_int16_t ss_sysaddr;
    u_int32_t sc_id; u_int32_t sc_unit; u_int32_t sc_reserved[5];
};

int zapret_tun_fd(void) {
    struct zapret_ctl_info info;
    memset(&info, 0, sizeof(info));
    strncpy(info.ctl_name, "com.apple.net.utun_control", sizeof(info.ctl_name) - 1);
    for (int fd = 0; fd <= 1024; fd++) {
        struct zapret_sockaddr_ctl addr;
        socklen_t len = sizeof(addr);
        memset(&addr, 0, sizeof(addr));
        if (getpeername(fd, (struct sockaddr *)&addr, &len) != 0 || addr.sc_family != AF_SYSTEM) continue;
        if (info.ctl_id == 0 && ioctl(fd, ZAPRET_CTLIOCGINFO, &info) != 0) continue;
        if (addr.sc_id == info.ctl_id) return fd;
    }
    return -1;
}
