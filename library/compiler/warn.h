/* Name resolution
   Copyright (C) 2003 Greg Morrisett, AT&T
   This file is part of the Cyclone compiler.

   The Cyclone compiler is free software; you can redistribute it
   and/or modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2 of
   the License, or (at your option) any later version.

   The Cyclone compiler is distributed in the hope that it will be
   useful, but WITHOUT ANY WARRANTY; without even the implied warranty
   of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with the Cyclone compiler; see the file COPYING. If not,
   write to the Free Software Foundation, Inc., 59 Temple Place -
   Suite 330, Boston, MA 02111-1307, USA. */

#ifndef _WARN_H
#define _WARN_H

#include "absyn.h"

#include <position.h>
#include <stdio.h>

namespace Warn
{
  extern void reset (string_t<`H>);
  extern int print_warnings;

  extern int num_errors;
  extern int max_errors;
#if 0
  extern void post_error (error_t);
#endif
  extern bool error_p ();

  void vwarn (Position::seg_t, string_t fmt, parg_t ?);

  void warn (Position::seg_t, string_t fmt, ... inject parg_t)
    __attribute__ ((format (printf, 2, 3)));
  void flush_warnings ();

  void verr (Position::seg_t, string_t fmt, parg_t ?);

  void err (Position::seg_t, string_t fmt, ... inject parg_t)
    __attribute__ ((format (printf, 2, 3)));

  `a vimpos (string_t fmt, parg_t ?ap)
    __attribute__ ((noreturn));

  `a impos (string_t fmt, ... inject parg_t)
    __attribute__ ((format (printf, 1, 2), noreturn));

  `a vimpos_loc (Position::seg_t, string_t fmt, parg_t ?)
    __attribute__ ((noreturn));

  `a impos_loc (Position::seg_t, string_t fmt, ... inject parg_t)
    __attribute__ ((format (printf, 2, 3), noreturn));

  extern datatype Warg
  {
    String    (string_t          );
    Qvar      (Absyn::qvar_t     );
    Typ       (Absyn::type_t     );
    TypOpt    (Absyn::type_opt_t );
    Exp       (Absyn::exp_t      );
    Stmt      (Absyn::stmt_t     );
    Aggrdecl  (Absyn::aggrdecl_t );
    Tvar      (Absyn::tvar_t     );
    KindBound (Absyn::kindbound_t);
    Kind      (Absyn::kind_t     );
    Attribute (Absyn::attribute_t);
    Vardecl   (Absyn::vardecl_t  );
    Int       (int               );
  };

  typedef datatype Warg @warg_t;

  void verr2  (Position::seg_t, warg_t ?);
  void vwarn2 (Position::seg_t, warg_t ?);
  void err2  (Position::seg_t, ... inject warg_t);
  void warn2 (Position::seg_t, ... inject warg_t);
  `a vimpos2 (warg_t ?)                                 __attribute__ ((noreturn));
  `a  impos2 (... inject warg_t)                        __attribute__ ((noreturn));
  `a vimpos_loc2 (Position::seg_t, warg_t ?)            __attribute__ ((noreturn));
  `a  impos_loc2 (Position::seg_t, ... inject warg_t)   __attribute__ ((noreturn));
}

#endif
