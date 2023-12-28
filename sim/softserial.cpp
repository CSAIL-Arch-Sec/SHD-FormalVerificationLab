#include <stdio.h>
#include <ncurses.h>
#include <unistd.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <pthread.h>
#include "psp.h"
#include "softserial.h"

extern PrettySecureProcessor *psp_system;

static void softserial_quit_signal(int sig) {
    endwin();
    exit(0);
}

#ifdef USE_NCURSES_SERIAL
// ncurses version of softserial (unused now in favor of line buffered IO)
void softserial_do_io_curses(void) {
    setvbuf(stdin, NULL, _IONBF, 0);
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    signal(SIGINT, softserial_quit_signal);
    SCREEN* s = newterm(NULL, stdin, stdout);
    noecho();
    cbreak();
    nonl();

    // initscr();
    // printw("Hello world\n");
    // getch();
    // endwin();
    while (true) {
        int val = getch();

        // printf("Sending %c to PSP...\n\r", val);

        bool succeeded_in_sending = false;

        while (!succeeded_in_sending) {
            pthread_mutex_lock(&psp_system->interrupt_lock);
            if (!psp_system->serial_data_available) {
                psp_system->serial_data_available = true;
                psp_system->serial_data = val;
                succeeded_in_sending = true;
                // printf("Success\n\r");
            }
            pthread_mutex_unlock(&psp_system->interrupt_lock);
            usleep(SOFTSERIAL_POLL_PERIOD);
        }

    }
}
#endif

void send_char_to_psp(char c) {
    bool succeeded_in_sending = false;

    while (!succeeded_in_sending) {
        pthread_mutex_lock(&psp_system->interrupt_lock);
        if (!psp_system->serial_data_available) {
            psp_system->serial_data_available = true;
            psp_system->serial_data = c;
            succeeded_in_sending = true;
        }
        pthread_mutex_unlock(&psp_system->interrupt_lock);
        usleep(SOFTSERIAL_POLL_PERIOD);
    }
}

// Line buffered softserial thread
void softserial_do_io(void) {
    setvbuf(stdin, NULL, _IONBF, 0);
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    while (true) {
        char linebuf[256];
        send_char_to_psp(fgetc(stdin));
        // if (fgets(linebuf, sizeof(linebuf), stdin)) {
        //     char *cursor = linebuf;
        //     while (*cursor) {
        //         send_char_to_psp(*cursor);
        //         cursor++;
        //     }
        // }
    }
}
