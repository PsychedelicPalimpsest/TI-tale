/* Hello world. See Makefile for building commands */

/* Description string for Ti calcs.  In apps this should be 8 or less characters or it can not be sent.*/
#pragma string name UNDRTALE


#include <stdio.h>

extern void reset_pen();

int main(){
    reset_pen();
    fputc_cons_native('!');
    fputc_cons_native('a');
    fputc_cons_native('p');

    while (1);
}
