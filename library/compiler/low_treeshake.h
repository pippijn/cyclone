/* Post-translation tree-shaking
 * Copyright (C) 2004 Dan Grossman, AT&T
 * This file is part of the Cyclone compiler.
 *
 * The Cyclone compiler is free software; you can redistribute it
 * and/or modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * The Cyclone compiler is distributed in the hope that it will be
 * useful, but WITHOUT ANY WARRANTY; without even the implied warranty
 * of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with the Cyclone compiler; see the file COPYING. If not,
 * write to the Free Software Foundation, Inc., 59 Temple Place -
 * Suite 330, Boston, MA 02111-1307, USA. */

// This is an optional pass that removes structs, enums, and (TO DO) externs
// that are not used.  It runs on C code, not Cyclone code.

#ifndef _LOW_TREESHAKE_H
#define _LOW_TREESHAKE_H

#include "absyn.h"

namespace LowTreeShake
{
  List::list_t<Absyn::decl_t> shake (List::list_t<Absyn::decl_t, `H>);
}

#endif
