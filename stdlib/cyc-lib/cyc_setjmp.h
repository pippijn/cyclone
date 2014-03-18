#ifndef _SETJMP_H_
#define _SETJMP_H_
#ifndef ___jmp_buf_def_
#define ___jmp_buf_def_
typedef int __jmp_buf[6U];
#endif
#ifndef ___sigset_t_def_
#define ___sigset_t_def_
typedef struct {unsigned long __val[1024U / (8U * sizeof(unsigned long))];} __sigset_t;
#endif
#ifndef ___jmp_buf_tag_def_
#define ___jmp_buf_tag_def_
 struct __jmp_buf_tag {
  __jmp_buf __jmpbuf;
  int __mask_was_saved;
  __sigset_t __saved_mask;
};
#endif
#ifndef _jmp_buf_def_
#define _jmp_buf_def_
typedef struct __jmp_buf_tag jmp_buf[1U];
#endif
extern int setjmp(jmp_buf);
#endif
