#pragma string name UNDRTALE

#include "globalc.h"


int main(){
    *current_light_buff = light_buff_1;
    *current_dark_buff = grey_buff_1;

    for (int i = 0; i < 64; ++i) {
        int base = i * (64/8) + 1;
        light_buff_1[base] = 0xFF;

        grey_buff_1[base +1] = 0xFF;

        light_buff_1[base +2] = 0xFF;
        grey_buff_1[base +2] = 0xFF;
    }



    while (1) __asm__("HALT");
}
