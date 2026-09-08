	.text
	.globl _start
_start:
	lea	ltab(%rip), %r12
	mov	$8, %r13
	sub	$128, %rsp
loop:
	mov	(%r12), %eax
	xor	%ecx, %ecx
	cpuid
	mov	%eax, %r8d
	mov	%ebx, %r9d
	mov	%ecx, %r10d
	mov	%edx, %r11d
	mov	%rsp, %rdi
	mov	(%r12), %eax
	call	hex8
	movb	$32, (%rdi)
	inc	%rdi
	mov	%r8d, %eax
	call	hex8
	movb	$32, (%rdi)
	inc	%rdi
	mov	%r9d, %eax
	call	hex8
	movb	$32, (%rdi)
	inc	%rdi
	mov	%r10d, %eax
	call	hex8
	movb	$32, (%rdi)
	inc	%rdi
	mov	%r11d, %eax
	call	hex8
	movb	$10, (%rdi)
	inc	%rdi
	mov	%rdi, %rdx
	sub	%rsp, %rdx
	mov	%rsp, %rsi
	mov	$1, %edi
	mov	$1, %eax
	syscall
	add	$4, %r12
	dec	%r13
	jnz	loop
	mov	$60, %eax
	xor	%edi, %edi
	syscall
hex8:
	mov	$8, %ecx
1:	rol	$4, %eax
	mov	%eax, %esi
	and	$15, %esi
	cmp	$10, %esi
	jb	2f
	add	$39, %esi
2:	add	$48, %esi
	mov	%sil, (%rdi)
	inc	%rdi
	dec	%ecx
	jnz	1b
	ret
	.p2align 4
ltab:
	.long	0
	.long	1
	.long	7
	.long	0x80000000
	.long	0x80000001
	.long	0x80000002
	.long	0x80000003
	.long	0x80000004
