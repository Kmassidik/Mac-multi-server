#ifndef CPTY_H
#define CPTY_H

/* Open a pseudo-terminal pair with an initial window size.
 * On success returns 0 and fills *amaster / *aslave; on failure returns -1. */
int cpty_openpty(int *amaster, int *aslave, unsigned short rows, unsigned short cols);

/* Set the window size on a pty master fd (TIOCSWINSZ). Returns 0 / -1. */
int cpty_setsize(int fd, unsigned short rows, unsigned short cols);

#endif
