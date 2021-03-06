/* Utilities for control flow analysis.
   Copyright (C) 2001 Dan Grossman, Greg Morrisett
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
#ifndef CF_FLOWINFO_H
#define CF_FLOWINFO_H

#include "absyn.h"

#include <dict.h>
#include <set.h>

// Note: Okasaki's dictionaries may be the wrong thing here because
//       we're doing a lot of intersections.  I don't know what's better,
//       but we do have all the dictionarys' domains known in advance, so
//       there probably is something better.

// A cute hack to avoid defining the abstract syntax twice.
#ifdef CF_FLOWINFO_CYC
#define EXTERN_CFFLOW
#else
#define EXTERN_CFFLOW extern
#endif

namespace CfFlowInfo
{
  extern bool anal_error;
  extern void aerr (Position::seg_t, string_t, ... inject parg_t)
    __attribute__ ((format (printf, 2, 3)));

  // Do not ever mutate any data structures built from these -- they share a lot!
  EXTERN_CFFLOW datatype Root
  {
    VarRoot (Absyn::vardecl_t);
    // the type below is the type of the result of the malloc
    MallocPt (Absyn::exp_t, Absyn::type_t); // misnamed when do other analyses??
    InitParam (int, Absyn::type_t); // int is parameter number, type is w/o @
  };
  typedef datatype Root @root_t;

  EXTERN_CFFLOW datatype PathCon
  {
    Dot (int num);
    Star;
  };
  typedef datatype PathCon @pathcon_t;
  typedef List::list_t<pathcon_t> path_t;

  EXTERN_CFFLOW struct Place
  {
    root_t root;
    path_t path;
    //the "path" of projections off the root -- these correspond to
    //either to dereferences (Star) or tuple offsets or field names (Dot
    //i).  The star is only sensible if it's dereferencing a unique
    //pointer.  For field names, we use the order in the struct
    //declaration to determine the index.  For example, x[0][1] would
    //have fields 0 and 1 if x is a tuple, while x.tl.tl would have
    //fields 1 and 1 if tl was the second field.
  };
  typedef struct Place @place_t;

  EXTERN_CFFLOW enum InitLevel
  {
    NoneIL, // may not be initialized
    AllIL // initialized, and everything it points to is initialized
  };
  typedef enum InitLevel initlevel_t;

  //////////////////////////////////////////////////////////////////////

  @extensible datatype Absyn::AbsynAnnot
  {
    EXTERN_CFFLOW IsZero;
    EXTERN_CFFLOW NotZero;
    EXTERN_CFFLOW UnknownZ;
  };
  extern_datacon (Absyn::AbsynAnnot, IsZero);
  extern_datacon (Absyn::AbsynAnnot, NotZero);
  extern_datacon (Absyn::AbsynAnnot, UnknownZ);

  EXTERN_CFFLOW @tagged union AbsLVal
  {
    place_t PlaceL;
    int UnknownL;   // int unused
  };
  typedef union AbsLVal absLval_t;
  extern absLval_t PlaceL (place_t);
  extern absLval_t UnknownL ();

  EXTERN_CFFLOW datatype AbsRVal;
  typedef datatype AbsRVal @absRval_t;
  typedef datatype AbsRVal *absRval_opt_t;
  typedef Dict::dict_t<root_t, absRval_t> flowdict_t;
  typedef absRval_t ?aggrdict_t;
  EXTERN_CFFLOW struct UnionRInfo
  {
    bool is_union; // true iff this aggregate represents a union
    int fieldnum; // last field written, if known; -1 otherwise
  };
  typedef struct UnionRInfo union_rinfo_t;
  EXTERN_CFFLOW datatype AbsRVal
  {
    Zero;    // the value is zero and initialized
    NotZeroAll; // the value is not zero & everything reachable from it is init
    UnknownR (initlevel_t); // don't know what the value is
    Esc (initlevel_t); // as an rval means same thing as UnknownR!!
    AddressOf (place_t); // I am a pointer to this place; implies not zero
    UniquePtr (absRval_t); // An anonymous unique pointer; does not imply not zero
    // if you're a tagged union, struct, or tuple, you should always
    // evaluate to an Aggregate in the abstract interpretation (datatype?)
    Aggregate (union_rinfo_t, aggrdict_t);
    Consumed (Absyn::exp_t consumer, int iteration, absRval_t oldvalue, bool local_alias);
    //the local_alias field is used for updating tryflows in the case where the
    //`U/`RC pointer is consumed by using an alias<`r> pattern. In this case, we
    //do not want to treat the `U ptr as consumed in the catch block, nor in the try's
    //continuation
    NamedLocation (Absyn::vardecl_t name, absRval_t actvalue);
    // A NamedLocation is simply a name for a location.  This is used to
    // track the value pointed to by a unique pointer for a function
    // parameter having the noconsume(x) attribute.  The name part never
    // changes, so can be compared via physical equality.
  };

  // Note: It would be correct to make the domain of the flowdict_t
  //       constant (all roots in the function), but it easy to argue
  //       that we at program point p, we only need those roots that
  //       are the target of an AddressOf or are locals in scope (so they
  //       might be mentioned explicitly in the program text).  A property
  //       of the analysis must be that at least these roots stay in the dict;
  //       for scalability, we don't have others.
  // join takes the intersection of the dictionaries.
  EXTERN_CFFLOW @tagged union FlowInfo
  {
    int BottomFL; // int unused
    flowdict_t ReachableFL;
  };
  typedef union FlowInfo flow_t;
  extern flow_t BottomFL ();
  extern flow_t ReachableFL (flowdict_t);

  // FIX: get rid of this since we heap-allocate!
  EXTERN_CFFLOW struct FlowEnv
  {
    absRval_t zero;
    absRval_t notzeroall;
    absRval_t unknown_none;
    absRval_t unknown_all;
    absRval_t esc_none;
    absRval_t esc_all;
    flowdict_t mt_flowdict;
    place_t dummy_place;
  };
  typedef struct FlowEnv @flow_env_t;  // FIX: remove
  extern flow_env_t new_flow_env (); //FIX: remove

  extern int get_field_index (Absyn::type_t t, Absyn::field_name_t f);
  extern int get_field_index_fs (List::list_t<Absyn::aggrfield_t> fs, Absyn::field_name_t f);
  extern int root_cmp (root_t, root_t);
  extern int place_cmp (place_t, place_t);

  extern aggrdict_t aggrfields_to_aggrdict (flow_env_t, List::list_t<struct Absyn::Aggrfield @>, bool no_init_bits_only, absRval_t);
  extern absRval_t typ_to_absrval (flow_env_t, Absyn::type_t, bool no_init_bits_only, absRval_t leafval);
  extern absRval_t make_unique_consumed (flow_env_t, Absyn::aqualbnds_t, Absyn::type_t, Absyn::exp_t consumer, int iteration, absRval_t, bool);
  extern bool is_unique_consumed (Absyn::exp_t, int env_iteration, absRval_t, bool @needs_unconsume);
  extern absRval_t make_unique_unconsumed (flow_env_t, absRval_t);
  extern $(absRval_t, List::list_t<Absyn::vardecl_t>) unname_rval (absRval_t);

  extern initlevel_t initlevel (flow_env_t, flowdict_t, absRval_t);
  extern absRval_t lookup_place (flowdict_t, place_t);
  extern bool is_unescaped (flowdict_t, place_t);
  extern bool is_init_pointer (absRval_t);
  extern bool flow_lessthan_approx (flow_t, flow_t);

  extern void print_absrval (absRval_t);
  extern void print_initlevel (initlevel_t);
  extern void print_root (root_t);
  extern void print_path (path_t);
  extern void print_place (place_t);
  extern void print_list (List::list_t<`a>, void (@) (`a));
  extern void print_flowdict (flowdict_t);
  extern void print_flow (flow_t);

  // debugging
  //#define DEBUG_FLOW

#ifdef DEBUG_FLOW
  extern bool debug_msgs;
#define DEBUG_PRINT(arg ...) if (debug_msgs) fprintf (stderr, ## arg)
#define DEBUG_PRINT_F(f, arg ...) if (debug_msgs) f (arg)
#else
#define DEBUG_PRINT_F(f, arg ...) { }
#define DEBUG_PRINT(arg ...) { }
#endif

  // all of the following throw EscNotInit as appropriate
  // the field list in the thrown place_t might be empty even if it shouldn't be
  extern flowdict_t escape_deref (flow_env_t, flowdict_t, absRval_t);
  extern flowdict_t assign_place (flow_env_t, Position::seg_t, flowdict_t,
                                  place_t, absRval_t);
  extern flow_t join_tryflow (flow_env_t, flow_t, flow_t);
  extern flow_t join_flow (flow_env_t, flow_t, flow_t);
  extern $(flow_t, absRval_t) join_flow_and_rval (flow_env_t,
                                                  $(flow_t, absRval_t),
                                                  $(flow_t, absRval_t));
  extern string_t place_err_string (place_t);
}

#endif
