// This is a C header file to be used by the output of the Cyclone
// to C translator.  The corresponding definitions are in
// the file lib/runtime_cyc.c

#ifndef _CYC_INCLUDE_H_
#define _CYC_INCLUDE_H_

//// Strings
struct _tagged_string { 
  unsigned char *curr; 
  unsigned char *base; 
  unsigned char *last_plus_one; 
};
extern struct _tagged_string xprintf(char *fmt, ...);

//// Discriminated Unions
struct _xtunion_struct { char *tag; };

// The runtime maintains a stack that contains either _handler_cons
// structs or _RegionHandle structs.  The tag is 0 for a handler_cons
// and 1 for a region handle.  
struct _RuntimeStack {
  int tag; // 0 for an exception handler, 1 for a region handle
  struct _RuntimeStack *next;
};

//// Regions
struct _RegionPage {
  struct _RegionPage *next;
#ifdef CYC_REGION_PROFILE
  unsigned int total_bytes;
  unsigned int free_bytes;
#endif CYC_REGION_PROFILE
  char data[0];
};

struct _RegionHandle {
  struct _RuntimeStack s;
  struct _RegionPage *curr;
  char               *offset;
  char               *last_plus_one;
};

extern struct _RegionHandle _new_region();
extern void * _region_malloc(struct _RegionHandle *, unsigned int);
extern void   _free_region(struct _RegionHandle *);

//// Exceptions 
#include <setjmp.h>
struct _handler_cons {
  struct _RuntimeStack s;
  jmp_buf handler;
};
extern void _push_handler(struct _handler_cons *);
extern void _push_region(struct _RegionHandle *);
extern void _npop_handler(int);
extern void _pop_handler();
extern void _pop_region();

extern void _throw(void * e);

extern struct _xtunion_struct *_exn_thrown;

//// Built-in Exceptions
extern struct _xtunion_struct _Null_Exception_struct;
extern struct _xtunion_struct * Null_Exception;
extern struct _xtunion_struct _Match_Exception_struct;
extern struct _xtunion_struct * Match_Exception;

//// Built-in Run-time Checks
static inline void * _check_null(void * ptr) {
  // caller casts result back to right type
  if(!ptr)
    _throw(Null_Exception);
  return ptr;
}
static inline char * _check_unknown_subscript(struct _tagged_string arr, 
					      unsigned elt_sz, unsigned index) {
  // caller casts first argument and result
  // multiplication looks inefficient, but C compiler has to insert it otherwise
  // by inlining, it should be able to avoid actual multiplication
  unsigned char * ans = arr.curr + elt_sz*index;
  if(!arr.base || ans < arr.base || ans >= arr.last_plus_one)
    _throw(Null_Exception);
  return ans;
}
static inline char * _check_known_subscript_null(void * ptr, 
						 unsigned bound,
						 unsigned elt_sz,
						 unsigned index) {
  if(!ptr || index > bound)
    _throw(Null_Exception);
  return ((char *)ptr) + elt_sz*index;
}
static inline unsigned _check_known_subscript_notnull(unsigned bound,
						      unsigned index) {
  if(index > bound)
    _throw(Null_Exception);
  return index;
}
				  
//// Allocation
extern void * GC_malloc(int);
extern void * GC_malloc_atomic(int);
#ifdef CYC_REGION_PROFILE
extern void * GC_profile_malloc(int,char *file,int lineno);
extern void * GC_profile_malloc_atomic(int,char *file,int lineno);
extern void * _profile_region_malloc(struct _RegionHandle *, unsigned int,
                                     char *file,int lineno);
#define GC_malloc(n) GC_profile_malloc(n,__FUNCTION__,__LINE__)
#define GC_malloc_atomic(n) GC_profile_malloc_atomic(n,__FUNCTION__,__LINE__)
#define _region_malloc(rh,n) _profile_region_malloc(rh,n,__FUNCTION__,__LINE__)
#endif

#endif