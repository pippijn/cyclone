/* $Id: xp.h,v 1.1 2004-07-06 17:49:20 gwprice Exp $ */
#ifndef XP_INCLUDED
#define XP_INCLUDED
#define T XP_T
#define DIGIT XPDIGIT_T
typedef unsigned char DIGIT;
typedef DIGIT ?@nozeroterm T;
extern int XP_add(int n, T z, T x, T y, int carry);
extern int XP_sub(int n, T z, T x, T y, int borrow);
extern int XP_mul(T z, int n, T x, int m, T y);
extern int XP_div(int n, T q, T x, int m, T y, T r,T tmp);
extern int XP_sum     (int n, T z, T x, int y);
extern int XP_diff    (int n, T z, T x, int y);
extern int XP_product (int n, T z, T x, int y);
extern int XP_quotient(int n, T z, T x, int y);
extern int XP_neg(int n, T z, T x, int carry);
extern int XP_cmp(int n, T x, T y);
extern void XP_lshift(int n, T z, int m, T x,
	int s, int fill);
extern void XP_rshift(int n, T z, int m, T x,
	int s, int fill);
extern void XP_and(int n, T z, T x, T y);
extern void XP_or(int n, T z, T x, T y);
extern void XP_xor(int n, T z, T x, T y);
extern int           XP_length (int n, T x);
extern unsigned long XP_fromint(int n, T z,
	unsigned long u);
extern unsigned long XP_toint  (int n, T x);
extern int   XP_fromstr(int n, T z, const char *str,
	int base);
extern char ?`r XP_tostr  (char ?`r str,
	int size, int base, int n, T x);
#undef T
#endif
