/* Utility functions for type checking.
   Copyright (C) 2001 Greg Morrisett, AT&T
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
#ifndef _TCUTIL_H_
#define _TCUTIL_H_

#include <set.h>
#include "tcenv.h"

namespace Tcutil {
using List;
using Absyn;
using Tcenv;

///////////////////  Warnings and Error messages ///////////////////////
extern `a impos(string_t, ... inject parg_t)
   __attribute__((format(printf,1,2), noreturn)) ;
extern void terr(seg_t, string_t, ... inject parg_t)
   __attribute__((format(printf,2,3))) ;
extern void warn(seg_t, string_t, ... inject parg_t)
  __attribute__((format(printf,2,3))) ;

////////////////  Predicates and Destructors for Types /////////////////
// Pure predicates
extern bool is_void_type(type_t);       // void
extern bool is_char_type(type_t);       // char, signed char, unsigned char
extern bool is_any_int_type(type_t);    // char, short, int, etc.
extern bool is_any_float_type(type_t);  // any size or sign
extern bool is_integral_type(type_t);   // any_int or tag_t or enum
extern bool is_arithmetic_type(type_t); // integral or any_float
extern bool is_signed_type(type_t);     // signed
extern bool is_function_type(type_t t); // function type
extern bool is_pointer_type(type_t t);  // pointer type
extern bool is_array_type(type_t t);    // array type
extern bool is_boxed(type_t t);         // boxed type

// Predicates that may constrain things
extern bool is_fat_ptr(type_t t); // fat pointer type
extern bool is_zeroterm_pointer_type(type_t t); // @zeroterm pointer type
extern bool is_nullable_pointer_type(type_t t); // nullable pointer type
extern bool is_bound_one(ptrbound_t b);         
// returns true if this is a t ? -- side effect unconstrained bounds
extern bool is_fat_pointer_type(type_t);
// returns true iff t contains only "bits" and no pointers or datatypes. 
// This is used to restrict the members of unions to ensure safety.
extern bool is_bits_only_type(type_t t);
// does the function (or fn pointer) type have the "noreturn" attribute?
extern bool is_noreturn_fn_type(type_t);

// Deconstructors for types

// return the element type for a pointer type
extern type_t pointer_elt_type(type_t t);
// return the region for a pointer type
extern type_t pointer_region(type_t t);
// If the given type is a pointer type, returns the region it points
// into.  Returns NULL if not a pointer type.
extern bool rgn_of_pointer(type_t t, type_t @rgn);
// For a thin bound, returns the associated expression, and for a fat 
// bound, returns null.  If b is unconstrained, then sets it to def.
extern exp_opt_t get_bounds_exp(ptrbound_t def, ptrbound_t b);
// Extracts the number of elements for an array or pointer type.
// If the bounds are unconstrained, then sets them to @thin@numelts(1).
extern exp_opt_t get_type_bound(type_t t);
// like is_fat_pointer_type, but puts element type in elt_dest when true.
extern bool is_fat_pointer_type_elt(type_t t, type_t@ elt_dest);
// like above but checks to see if the pointer is zero-terminated
extern bool is_zero_pointer_type_elt(type_t t, type_t@ elt_type_dest);
// like above but also works for arrays and returns dynamic pointer stats
extern bool is_zero_ptr_type(type_t t, type_t @ptr_type, 
			     bool @is_fat, type_t @elt_type);
// if b is fat return NULL, if it's thin(e), return e, if
// it's unconstrained, constrain it to def and return that.
extern exp_opt_t get_bounds_exp(ptrbound_t def, ptrbound_t b);

//////////////////////// UTILITIES for Expressions ///////////////
extern bool is_integral(exp_t); 
extern bool is_numeric(exp_t);
extern bool is_zero(exp_t e);

// returns a deep copy of a type -- note that the evars will
// still share and if the identity is set on type variables,
// they will share, otherwise they won't.
extern type_t copy_type(type_t t);
// deep copy of an expression; uses copy_type above, so same rules apply.
// if [preserve_types], then copies the type, too; otherwise null
extern exp_t deep_copy_exp(bool preserve_types, exp_t);

// returns true if kind k1 is a sub-kind of k2
extern bool kind_leq(kind_t k1, kind_t k2);

// returns the type of a function declaration
extern type_t fd_type(fndecl_t fd); 
extern kind_t tvar_kind(tvar_t t,kind_t def);
extern kind_t type_kind(type_t t);
extern bool kind_eq(kind_t k1, kind_t k2);
extern type_t compress(type_t t);
extern void unchecked_cast(tenv_t, exp_t, type_t, coercion_t);
extern bool coerce_arg(tenv_t, exp_t, type_t, bool@ alias_coercion); 
extern bool coerce_assign(tenv_t, exp_t, type_t);
extern bool coerce_to_bool(tenv_t, exp_t);
extern bool coerce_list(tenv_t, type_t, list_t<exp_t>);
extern bool coerce_uint_type(tenv_t, exp_t);
extern bool coerce_sint_type(tenv_t, exp_t);
extern bool coerce_use(tenv_t, exp_t, type_t);
// true when expressions of type t1 can be implicitly cast to t2
extern bool silent_castable(tenv_t,seg_t,type_t,type_t);
// true when expressions of type t1 can be cast to t2 -- call silent first
extern coercion_t castable(tenv_t,seg_t,type_t,type_t);
// true when t1 is a subtype of t2 under the given list of subtype assumptions
extern bool subtype(tenv_t te, list_t<$(type_t,type_t)@`H,`H> assume, 
                    type_t t1, type_t t2);

// used to alias the given expression, assumed to have non-Aliasable type
extern $(decl_t,exp_t) insert_alias(exp_t e, type_t e_typ);
// prints a warning when an alias coercion is inserted
extern bool warn_alias_coerce;
// flag to control whether or not we print a warning when implicitly casting
// a pointer from one region into another due to outlives constraints.
extern bool warn_region_coerce;


// useful kinds
extern struct Kind rk; // shareable region kind
extern struct Kind ak; // shareable abstract kind
extern struct Kind bk; // shareable boxed kind
extern struct Kind mk; // shareable mem kind
extern struct Kind ek; // effect kind
extern struct Kind ik; // int kind
extern struct Kind boolk; // boolean kind
extern struct Kind ptrbk; // pointer bound kind

extern struct Kind trk; // top region kind
extern struct Kind tak; // top abstract kind
extern struct Kind tbk; // top boxed kind
extern struct Kind tmk; // top memory kind

extern struct Kind urk;  // unique region kind
extern struct Kind uak;  // unique abstract kind
extern struct Kind ubk;  // unique boxed kind
extern struct Kind umk;  // unique memory kind

extern struct Core::Opt<kind_t> rko;
extern struct Core::Opt<kind_t> ako;
extern struct Core::Opt<kind_t> bko;
extern struct Core::Opt<kind_t> mko;
extern struct Core::Opt<kind_t> iko;
extern struct Core::Opt<kind_t> eko;
extern struct Core::Opt<kind_t> boolko;
extern struct Core::Opt<kind_t> ptrbko;

extern struct Core::Opt<kind_t> trko;
extern struct Core::Opt<kind_t> tako;
extern struct Core::Opt<kind_t> tbko;
extern struct Core::Opt<kind_t> tmko;

extern struct Core::Opt<kind_t> urko;
extern struct Core::Opt<kind_t> uako;
extern struct Core::Opt<kind_t> ubko;
extern struct Core::Opt<kind_t> umko;

extern Core::opt_t<kind_t> kind_to_opt(kind_t k);
extern kindbound_t kind_to_bound(kind_t k);
extern bool unify_kindbound(kindbound_t, kindbound_t);

extern $(tvar_t,kindbound_t) swap_kind(type_t t, kindbound_t kb);
  // for temporary kind refinement

// if t is a pointer type and e is 0, changes e to null and checks
// that t is nullable pointer type by unifying e's type with t.
extern bool zero_to_null(tenv_t, type_t t, exp_t e);

extern type_t max_arithmetic_type(type_t, type_t);

// explain_failure() explains why unify failed and at what particular types.
// Output goes to stderr.
extern void explain_failure();

extern bool unify(type_t, type_t);
  // linear order on types (needed for dictionary indexing)
extern int typecmp(type_t, type_t);
extern int aggrfield_cmp(aggrfield_t, aggrfield_t); // used in toc.cyc

extern type_t substitute(list_t<$(tvar_t,type_t)@`H,`H>, type_t);
  // could also have a version with two regions, but doesn't seem useful
extern type_t rsubstitute(region_t<`r>,list_t<$(tvar_t,type_t)@`r,`r>,type_t);
extern list_t<$(type_t,type_t)@> rsubst_rgnpo(region_t<`r>,
					      list_t<$(tvar_t,type_t)@`r,`r>,
					      list_t<$(type_t,type_t)@`H,`H>);

// substitute through an expression
extern exp_t rsubsexp(region_t<`r> r, list_t<$(tvar_t,type_t)@`r,`r>, exp_t);

// true when e1 is a sub-effect of e2
extern bool subset_effect(bool may_constrain_evars, type_t e1, type_t e2);

// returns true when rgn is in effect -- won't side-effect any evars when
// constrain is false.
extern bool region_in_effect(bool constrain, type_t r, type_t e);

extern type_t fndecl2type(fndecl_t);

// generate an appropriate evar for a type variable -- used in
// instantiation.  The list of tvars is used to constrain the evar.
extern $(tvar_t,type_t)@   make_inst_var(list_t<tvar_t,`H>,tvar_t);
extern $(tvar_t,type_t)@`r r_make_inst_var($(list_t<tvar_t,`H>,region_t<`r>)@,tvar_t);
					   

// checks that a width given on a struct or union member is consistent
// with the type definition for the member.
extern void check_bitfield(seg_t loc, tenv_t te, type_t field_typ, 
                           exp_opt_t width, stringptr_t fn);

// Checks that a type is well-formed and lives in kind k.  The input
// list of type variables is used to constrain the kinds and identities
// of the free type variables in the type.  Returns the list of free
// type variables in the type.
//
// This also performs the following side-effects which most of the 
// rest of the compiler rightfully assumes have occurred:
// * expand typedefs
// * set pointers to declarations for StructType, DatatypeType
// * change relative type names to absolute type names
// * set the kind field of type variables: we use the expected kind
//   initially, but if later constraints force a more constrained kind,
//   then we move to the more constrained kind.  
// * add default effects for function types -- the default effect
//   causes a fresh EffKind type variable e to be generated, and
//   consists of e and any free effect or region variables within
//   the function type.
// * ensures that for any free evar in the type, it can only be 
//   constrained with types whose free variables are contained in the
//   set of free variables returned.
  // extern list_t<tvar_t> check_valid_type(seg_t,tenv_t,list_t<tvar_t>,kind_t k,type_t);
// Similar to the above except that (a) there are no bound type variables,
// (b) for function types, we bind the free type variables, (c) the expected
// kind defaults to MemKind.
extern void check_valid_toplevel_type(seg_t,tenv_t,type_t);
// Special cased for function declarations
extern void check_fndecl_valid_type(seg_t,tenv_t,fndecl_t);
// Same as check_valid_type but ensures that the resulting free variables
// are compatible with a set of bound type variables.  Note that this
// the side effect of constraining the kinds of the bound type variables.
// In addition, if allow_evars is true, then the evars in the type are
// unconstrained.  Otherwise, we set all region evars to the heap and
// all effect evars to the empty set, and signal an error for a free type
// evar.
extern void check_type(seg_t, tenv_t, list_t<tvar_t,`H> bound_tvars, kind_t k,
                       bool allow_evars, bool allow_abs_aggr, type_t);

extern void check_unique_vars(list_t<var_t,`r> vs, seg_t loc, string_t err_msg);
extern void check_unique_tvars(seg_t,list_t<tvar_t>);

// Sees if the unique region `U occurs in the type t
//  extern void check_no_unique_region(seg_t loc, tenv_t te, type_t t);

// Check that bounds are not zero -- constrain to 1 if necessary
extern void check_nonzero_bound(seg_t, ptrbound_t);
// Check that bounds are greater than i -- constrain to i+1 if necessary
extern void check_bound(seg_t, unsigned int i, ptrbound_t, bool do_warn);

extern list_t<$(aggrfield_t,`a)@`r,`r> 
resolve_aggregate_designators(region_t<`r>rgn, seg_t loc,
                              list_t<$(list_t<designator_t>,`a)@`r2,`r3> des, 
                              aggr_kind_t, // struct or union
                              list_t<aggrfield_t> fields);
// is e1 of the form *ea or ea[eb] where ea is a zero-terminated pointer?
// If so, return true and set ea and eb appropriately (for *ea set eb to 0).
// Finally, if the pointer is fat, set is_fat.
extern bool is_zero_ptr_deref(exp_t e1, type_t @ptr_type, 
			      bool @is_fat, type_t @elt_type);
			      

// returns true if this a non-aliasable region, e.g. `U, `r::TR, etc.
extern bool is_noalias_region(type_t r, bool must_be_unique);

// returns true if this a non-aliasable pointer, e.g. *`U, *`r::TR, etc.
extern bool is_noalias_pointer(type_t t, bool must_be_unique);

// returns true if this expression only deferences non-aliasable pointers
// and if the ultimate result is a noalias pointer or aggregate.  The
// region is used for allocating temporary stuff.
extern bool is_noalias_path(exp_t e);

// returns true if this expression is an aggregate that contains
// non-aliasable pointers or is itself a non-aliasable pointer
// The region is used for allocating temporary stuff
extern bool is_noalias_pointer_or_aggr(type_t t);

// Ensure e is an lvalue or function designator -- return whether
// or not &e is const and what region e is in.
extern $(bool,type_t) addressof_props(tenv_t te, exp_t e);

// Given an effect, express/mutate it to have only regions(`a), `r, and joins.
extern type_t normalize_effect(type_t e);

// Gensym a new type variable with kind bounded by k
extern tvar_t new_tvar(kindbound_t k);
// Get an identity for a type variable
extern int new_tvar_id();
// Add an identity to a type variable if it doesn't already have one
extern void add_tvar_identity(tvar_t);
extern void add_tvar_identities(list_t<tvar_t,`r>);
// true iff t has been generated by new_tvar (#xxx)
extern bool is_temp_tvar(tvar_t);
// in this case, we may want to rewrite it in `txxx (before printing it)
extern void rewrite_temp_tvar(tvar_t);

// are the lists of attributes the same?  doesn't require the same order
extern bool same_atts(attributes_t, attributes_t);

// returns true iff e is an expression that can be evaluated at compile time
extern bool is_const_exp(exp_t e);

// like Core::snd, but first argument is a tqual_t (not a BoxKind)
extern type_t snd_tqt($(tqual_t,type_t)@);

// If t is a typedef, returns true if the typedef is const, and warns
// if the flag declared_const is true.  Otherwise returns declared_const.
extern bool extract_const_from_typedef(seg_t, bool declared_const, type_t);

// Transfer any function type attributes from the given list to the
// function type.  
extern attributes_t transfer_fn_type_atts(type_t t, attributes_t atts);

// issue a warning if the type is a typedef with non-empty qualifiers
extern void check_no_qual(seg_t loc, type_t t);

// If b is a non-escaping variable binding, return a non-null pointer to
// the vardecl.
extern struct Vardecl *nonesc_vardecl(binding_t b);

  // filters out null elements
extern list_t<`a> filter_nulls(list_t<`a *> l);

// If t is an array type, promote it to an at-pointer type into the
// specified region.
extern type_t promote_array(type_t t, type_t rgn, bool convert_tag);

// does the type admit zero?
extern bool zeroable_type(type_t t);

// try to constrain the boolean kinded type to desired and then
// convert it the type to a boolean.
extern bool force_type2bool(bool desired, type_t t);

// unconstrained boolean-kinded type node
extern type_t any_bool(tenv_t *te);
// unconstrained pointer bound type node
extern type_t any_bounds(tenv_t *te);

}
#endif
