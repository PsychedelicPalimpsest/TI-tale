all: out.8xk


out.8xk: first_page.c fputc_cons.asm Makefile
	zcc +ti83p -o out first_page.c fputc_cons.asm -crt0=custom_ti83papp_crt0.asm $(CFLAGS)

	z88dk-appmake +ti83papp --single-page --binfile out --crt0file custom_ti83papp_crt0.asm --output out.8xk
clean:
	rm -f out.8xk *.bin out *.lis
