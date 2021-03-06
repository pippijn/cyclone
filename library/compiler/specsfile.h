/* Handle Cyclone specs files.
   Copyright (C) 2004 Greg Morrisett, AT&T
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

#ifndef _SPECSFILE_H_
#define _SPECSFILE_H_

#include <arg.h>
#include <core.h>
#include <list.h>

namespace Specsfile {
  using List;
  using Core;
  extern string_t target_arch;
  extern void set_target_arch(string_t<`H> s);
  extern list_t<stringptr_t> cyclone_exec_path;
  extern void add_cyclone_exec_path(string_t s);
  typedef list_t<$(const char ?@,const char ?@)@> specs_t;
  extern specs_t read_specs(const char ?file);
  extern string_t<`H> ?`H split_specs(const char ?cmdline);
  extern const char ?get_spec(specs_t specs, const char ?spec_name);
  extern list_t<stringptr_t> cyclone_arch_path;
  extern string_t def_lib_path;
  extern const char ?@zeroterm ?parse_b(Arg::speclist_t<`r1,`r2> specs,
                                        void anonfun(string_t<`H>),
                                        bool anonflagfun(string_t<`H>),
                                        string_t errmsg,
                                        string_t<`H> ?`H argv);
  extern string_t find_in_arch_path(string_t s);
  extern string_t find_in_exec_path(string_t s);
}

#endif
