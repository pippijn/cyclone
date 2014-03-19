#include <stdio.h>
#include <wchar.h>

int
main (int argc, char *argv[])
{
  char const *arch;

  if (argc < 2)
    return 1;

#ifdef __i386__
  arch = "i386";
#elif defined(__x86_64__)
  arch = "x86_64";
#else
  arch = "unknown";
#endif

  printf ("char *Carch = \"%s\";\n", arch);
  printf ("char *Cdef_lib_path = \"%s/library/stdlib\";\n", argv[1]);
  printf ("char *Cversion = \"1.0\";\n");
  printf ("int Wchar_t_unsigned = %d;\n", (wchar_t)-1 > 0);
  printf ("int Sizeof_wchar_t = %d;\n", sizeof (wchar_t));

  return 0;
}
