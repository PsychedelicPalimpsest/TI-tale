#pragma string name UNDRTALE

#include "engine/globalc.h"
extern void greyscale_swap();

int main(){

    for (int i = 0; i < 64; ++i) {
        int base = i * (96/8) + 1;

        working_light[base] = 0xFF;
        working_dark[base +1] = 0xFF;

        working_light[base +2] = 0xFF;
        working_dark[base +2] = 0xFF;
    }
    greyscale_swap();



    while (1) ;
}
