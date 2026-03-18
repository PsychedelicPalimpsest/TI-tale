#pragma string name UNDRTALE

#include "globalc.h"


int main(){

    for (int i = 0; i < 64; ++i) {
        int base = i * (96/8) + 1;

        working_light[base] = 0xFF;
        working_dark[base +1] = 0xFF;

        working_light[base +2] = 0xFF;
        working_dark[base +2] = 0xFF;
    }



    while (1) ;
}
