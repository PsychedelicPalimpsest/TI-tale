#pragma string name UNDRTAL2

#include "core/globalc.h"
extern void greyscale_swap();


void* alloc() __naked {
  #asm
  ld hl, fheap_addr(heap1)
  fheap_alloc 2
  #endasm
}

// input = de
void free() __naked {
  #asm
  ld hl, fheap_addr(heap1)
  fheap_free
  ret
   #endasm
}

int main(){
  greyscale_swap();
  #asm
  fheap_def globals_area, heap1, 64, 2
  fheap_init_inline heap1

  ld ix, globals_area
  REPTI v, 1, 2, 3, 4, 5, 6, 6, 8
    push hl
    call _alloc
    ex de, hl
    pop hl
    
    ld (ix), de
    inc ix
    inc ix
  ENDR

  ld ix, globals_area

  ld de, (ix+2)
  call _free
  ld de, (ix+4)
  call _free


  ld hl, fheap_addr(heap1)
  fheap_foreach 2
    ; do whatever in here
    add hl, hl

    jp @loop
    @end_of_loop:

  






  #endasm


}

