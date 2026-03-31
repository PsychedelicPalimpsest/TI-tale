#pragma string name UNDRTAL2

#include "core/globalc.h"
extern void greyscale_swap();

int main(){

    for (int i = 0; i < (768*2); i += (96/8*2)) {
        // byte 1=light, byte 2=dark buffer
        screen_buffer[i+2] = 0xFF;

        screen_buffer[i+5] = 0xFF;

        screen_buffer[i+6] = 0xFF;
        screen_buffer[i+7] = 0xFF;

        screen_buffer[i+8] = 0xFF;
        screen_buffer[i+9] = 0xFF;

        screen_buffer[i+11] = 0xFF;

        screen_buffer[i+12] = 0xFF;
    
    }
    greyscale_swap();

    while (1) ;
}
