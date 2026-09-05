#include "cpty.h"
#include <util.h>       /* openpty on macOS */
#include <sys/ioctl.h>
#include <termios.h>

int cpty_openpty(int *amaster, int *aslave, unsigned short rows, unsigned short cols) {
    struct winsize ws;
    ws.ws_row = rows ? rows : 24;
    ws.ws_col = cols ? cols : 80;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    return openpty(amaster, aslave, NULL, NULL, &ws);
}

int cpty_setsize(int fd, unsigned short rows, unsigned short cols) {
    struct winsize ws;
    ws.ws_row = rows ? rows : 24;
    ws.ws_col = cols ? cols : 80;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    return ioctl(fd, TIOCSWINSZ, &ws);
}
