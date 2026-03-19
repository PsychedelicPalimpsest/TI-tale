#pragma string name UNDRTALE

#include "globalc.h"
extern void greyscale_swap();


int main(){

    // Assuming working buffers are at least 768 bytes (64 * 12)
    // and cleared to 0x00 before this loop starts.
    for (int i = 0; i < 64; ++i) {
        int base = i * 12; // 12 bytes per row (96 pixels)

        // Shade 0 (000): White
        // No action needed (all planes 0)

        // Shade 1 (001): W1 only
        working_w1[base + 1] = 0xFF;

        // Shade 2 (010): W2 only
        working_w2[base + 2] = 0xFF;

        // Shade 3 (011): W1 + W2
        working_w1[base + 3] = 0xFF;
        working_w2[base + 3] = 0xFF;

        // Shade 4 (100): W4 only
        working_w4[base + 4] = 0xFF;

        // Shade 5 (101): W4 + W1
        working_w4[base + 5] = 0xFF;
        working_w1[base + 5] = 0xFF;

        // Shade 6 (110): W4 + W2
        working_w4[base + 6] = 0xFF;
        working_w2[base + 6] = 0xFF;

        // Shade 7 (111): W4 + W2 + W1 (Black)
        working_w4[base + 7] = 0xFF;
        working_w2[base + 7] = 0xFF;
        working_w1[base + 7] = 0xFF;

        // Remaining bytes (8-11) will remain Shade 0 unless filled
    }
    greyscale_swap();



    while (1) ;
}
