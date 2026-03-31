all: out.8xk


CFLAGS = "-pragma-define:CRT_ENABLE_STDIO=0" -m
out.8xk: first_page.c  Makefile
	zcc +ti83p -o out first_page.c engine/greyscale_swap.asm utils/screenbg_blit2.asm -crt0=engine/custom_ti83papp_crt0.asm $(CFLAGS)

	z88dk-appmake +ti83papp --single-page --binfile out --crt0file engine/custom_ti83papp_crt0.asm --output out.8xk
clean:
	rm -f out.8xk *.bin out *.lis
