	.text
	.globl _start
_start:
	# write "A" then do 1/0 (32-bit div) then write "B"
	mov	$1, %eax
	mov	$1, %edi
	lea	msgA(%rip), %rsi
	mov	$2, %edx
	syscall
	xor	%edx, %edx
	mov	$1, %eax
	xor	%ecx, %ecx
	div	%ecx
	# survived: print result of eax
	mov	%eax, %r8d
	mov	$1, %eax
	mov	$1, %edi
	lea	msgB(%rip), %rsi
	mov	$2, %edx
	syscall
	mov	$60, %eax
	xor	%edi, %edi
	syscall
msgA:	.ascii	"A\n"
msgB:	.ascii	"B\n"
