/* Abstract syntax.
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

#ifndef _ABSYN_H_
#define _ABSYN_H_

// This file defines the abstract syntax used by the Cyclone compiler
// and related tools.  It is the crucial set of data structures that 
// pervade the compiler.  

// The abstract syntax has (at last count) three different "stages":
// A. Result of parsing
// B. Result of type-checking
// C. Result of translation to C
// Each stage obeys different invariants of which the compiler hacker
// (that's you) must be aware.
// Here is an invariant after parsing:
//  A1. qvars may be Rel_n, Abs_n, or Loc_n.
//      Rel_n is used for most variable references and declarations.
//      Abs_n is used for some globals (Null_Exception, etc).
//      Loc_n is used for some locals (comprehension and pattern variables).
// Here are some invariants after type checking:
//  B1. None of the following are used:
//        UnknownId_e, UnknownCall_e, UnresolvedMem_e
//      They have all been replaced by
//        Var_e, FnCall_e, Struct_e, Tunion_e, 
//      In Var_e, Unresolved_b is not used.
//  B2. All qvars are either Loc_n or Abs_n.  Any Rel_n has been
//      replaced by Loc_n or Abs_n.
//  B3. All "dest fields" and non_local_preds fields in stmt objects
//      are correct.
//  B4. Every expression has a non-null and correct type field.
//  B5. None of the "unresolved" variants are used.  (There may be 
//      underconstrained Evars for types.)
//  B6. The pat_vars field of switch_clause is non-null and correct.
// Note that translation to C willfully violates B3 and B4, but that's okay.
// The translation to C also eliminates all things like type variables.

// A cute hack to avoid defining the abstract syntax twice:
#ifdef ABSYN_CYC
#define EXTERN_ABSYN
#else
#define EXTERN_ABSYN extern
#endif

#include <core.h>
#include <list.h>
#include <position.h>

namespace Absyn {
  using Core;
  using List;
  using Position;
  
  typedef stringptr_t field_name_t; // field names (for structs, etc.)
  typedef stringptr_t var_t;        // variables are string pointers
  typedef stringptr_t tvarname_t;   // type variables

  // Name spaces
  EXTERN_ABSYN tunion Nmspace {
    Loc_n,                // Local name
    Rel_n(list_t<var_t>), // Relative name
    Abs_n(list_t<var_t>)  // Absolute name
  };
  typedef tunion Nmspace nmspace_t;

  // Qualified variables
  typedef $(nmspace_t,var_t) @qvar_t, *qvar_opt_t;
  typedef qvar_t typedef_name_t;
  typedef qvar_opt_t typedef_name_opt_t; 

  // forward declarations
  EXTERN_ABSYN struct Conref<`a>;
  EXTERN_ABSYN tunion Constraint<`a>;

  // typedefs -- in general, we define foo_t to be struct Foo@ or tunion Foo.
  typedef tunion Scope scope_t;
  typedef struct Tqual tqual_t; // not a pointer
  typedef tunion Size_of size_of_t;
  typedef tunion Kind kind_t;
  typedef tunion KindBound kindbound_t;
  typedef struct Tvar @tvar_t; 
  typedef tunion Sign sign_t;
  typedef tunion AggrKind aggr_kind_t;
  typedef struct Conref<`a> @conref_t<`a>;
  typedef tunion Constraint<`a> constraint_t<`a>;
  typedef tunion Bounds bounds_t;
  typedef struct PtrAtts ptr_atts_t;
  typedef struct PtrInfo ptr_info_t;
  typedef struct VarargInfo vararg_info_t;
  typedef struct FnInfo fn_info_t;
  typedef struct TunionInfo tunion_info_t;
  typedef struct TunionFieldInfo tunion_field_info_t;
  typedef struct AggrInfo aggr_info_t;
  typedef struct ArrayInfo array_info_t;
  typedef tunion Type type_t, rgntype_t;
  typedef tunion Funcparams funcparams_t;
  typedef tunion Type_modifier type_modifier_t;
  typedef tunion Cnst cnst_t;
  typedef tunion Primop primop_t;
  typedef tunion Incrementor incrementor_t;
  typedef struct VarargCallInfo vararg_call_info_t;
  typedef tunion Raw_exp raw_exp_t;
  typedef struct Exp @exp_t, *exp_opt_t;
  typedef tunion Raw_stmt raw_stmt_t;
  typedef struct Stmt @stmt_t, *stmt_opt_t;
  typedef tunion Raw_pat raw_pat_t;
  typedef struct Pat @pat_t;
  typedef tunion Binding binding_t;
  typedef struct Switch_clause @switch_clause_t;
  typedef struct SwitchC_clause @switchC_clause_t;
  typedef struct Fndecl @fndecl_t;
  typedef struct Aggrdecl @aggrdecl_t;
  typedef struct Tunionfield @tunionfield_t;
  typedef struct Tuniondecl @tuniondecl_t;
  typedef struct Typedefdecl @typedefdecl_t;
  typedef struct Enumfield @enumfield_t;
  typedef struct Enumdecl @enumdecl_t;
  typedef struct Vardecl @vardecl_t;
  typedef tunion Raw_decl raw_decl_t;
  typedef struct Decl @decl_t;
  typedef tunion Designator designator_t;
  typedef xtunion AbsynAnnot absyn_annot_t;
  typedef tunion Attribute attribute_t;
  typedef list_t<attribute_t> attributes_t;
  typedef struct Aggrfield @aggrfield_t;
  typedef tunion OffsetofField offsetof_field_t;
  typedef struct MallocInfo malloc_info_t;
  typedef struct ForArrayInfo forarray_info_t;

  // scopes for declarations 
  EXTERN_ABSYN tunion Scope { 
    Static,    // definition is local to the compilation unit
    Abstract,  // definition is exported only abstractly (structs only)
    Public,    // definition is exported in full glory (most things)
    Extern,    // definition is provided elsewhere
    ExternC,   // definition is provided elsewhere by C code 
    Register   // value may be stored in a register
  };

  // type qualifiers -- const, volatile, and restrict
  EXTERN_ABSYN struct Tqual { 
    bool q_const :1; bool q_volatile :1; bool q_restrict :1; 
  };

  // FIX: we should make this char, short, int, etc.  -- something
  // that's machine independent.
  // byte sizes -- 1, 2, 4, or 8 bytes
  EXTERN_ABSYN tunion Size_of { B1, B2, B4, B8 };

  // Used to classify types.  
  EXTERN_ABSYN tunion Kind { 
    // BoxKind <= MemKind <= AnyKind
    AnyKind, // kind of all types, including abstract structs
    MemKind, // excludes abstract structs
    BoxKind, // excludes types whose values dont go in general-purpose registers
    RgnKind, // regions
    EffKind, // effects
    IntKind  // constant ints
  };

  // signed or unsigned qualifiers on integral types
  EXTERN_ABSYN tunion Sign { Signed, Unsigned, None };

  EXTERN_ABSYN tunion AggrKind { StructA, UnionA };

  // constraint refs are used during unification to figure out what
  // something should be when it's under-specified
  EXTERN_ABSYN struct Conref<`a> { constraint_t<`a> v; };
  EXTERN_ABSYN tunion Constraint<`a> { 
    Eq_constr(`a), Forward_constr(conref_t<`a>), No_constr 
  };

  // kind bounds are used on tvar's to infer their kinds
  //   Eq_kb(k):  the tvar has kind k
  //   Unknown_kb(&Opt(kb)): follow the link to kb to determine bound
  //   Less_kb(&Opt(kb1),k): same, but link should be less than k
  //   Unknown_kb(NULL):  the tvar's kind is completely unconstrained
  //   Less_kb(NULL,k): the tvar's kind is unknown but less than k
  EXTERN_ABSYN tunion KindBound {
    Eq_kb(kind_t);        
    Unknown_kb(opt_t<kindbound_t>); 
    Less_kb(opt_t<kindbound_t>, kind_t); 
  };

  // type variables
  EXTERN_ABSYN struct Tvar {
    tvarname_t name;       // the user-level name of the type variable
    int       *identity;   // for alpha-conversion -- unique
    kindbound_t kind;
  };

  // used to distinguish ? pointers from *{c} or @{c} pointers
  EXTERN_ABSYN tunion Bounds {
    Unknown_b;      // t?
    Upper_b(exp_t); // t*{x:x>=0 && x < e} and t@{x:x>=0 && x < e}
    AbsUpper_b(type_t); // abstract bound -- type has IntKind
  };

  EXTERN_ABSYN struct PtrAtts {
    rgntype_t          rgn;       // region of value to which pointer points
    conref_t<bool>     nullable;  // type admits NULL (* vs. @)
    conref_t<bounds_t> bounds;    // legal bounds for pointer indexing
    conref_t<bool>     zero_term; // true => zero terminated array
  };

  // information about a pointer type
  EXTERN_ABSYN struct PtrInfo {
    type_t     elt_typ;  // type of value to which pointer points
    tqual_t    elt_tq;   // qualifier **for elements**
    ptr_atts_t ptr_atts;
  };

  // information about vararg functions
  EXTERN_ABSYN struct VarargInfo {
    opt_t<var_t> name;
    tqual_t tq;
    type_t  type;
    bool    inject;
  };

  // information for functions
  EXTERN_ABSYN struct FnInfo {
    list_t<tvar_t>  tvars;   // abstracted type variables
    // effect describes those regions that must be live to call the fn
    opt_t<type_t>   effect;  // null => default effect
    type_t          ret_typ; // return type
    // arguments are optionally named
    list_t<$(opt_t<var_t>,tqual_t,type_t)@>  args; 
    // if c_varargs is true, then cyc_varargs == null, and if 
    // cyc_varargs is non-null, then c_varargs is false.
    bool                                     c_varargs;
    vararg_info_t*                           cyc_varargs;
    // partial order on region parameters
    list_t<$(type_t,type_t)@>                rgn_po;
    // function type attributes can include regparm(n), noreturn, const
    // and at most one of cdecl, stdcall, and fastcall.  See gcc info
    // for documentation on attributes.
    attributes_t                             attributes; 
  };

  // information for [x]tunion's
  EXTERN_ABSYN struct UnknownTunionInfo {
    qvar_t name;       // name of the [x]tunion
    bool   is_xtunion; // true -> xtunion, false -> tunion
  };
  EXTERN_ABSYN tunion TunionInfoU {
    UnknownTunion(struct UnknownTunionInfo); // don't know definition yet
    KnownTunion(tuniondecl_t@);              // known definition
  };
  EXTERN_ABSYN struct TunionInfo {
    tunion TunionInfoU tunion_info; // we either know the definition or not
    list_t<type_t>     targs;       // actual type parameters
    rgntype_t          rgn;         // region into which tunion points
  };
  // information for [x]tunion Foo.Bar
  EXTERN_ABSYN struct UnknownTunionFieldInfo {
    qvar_t tunion_name;   // name of the [x]tunion 
    qvar_t field_name;    // name of the tunion field
    bool   is_xtunion;    // true -> xtunion, false -> tunion
  };
  EXTERN_ABSYN tunion TunionFieldInfoU {
    UnknownTunionfield(struct UnknownTunionFieldInfo);
    KnownTunionfield(tuniondecl_t, tunionfield_t);
  };
  EXTERN_ABSYN struct TunionFieldInfo {
    tunion TunionFieldInfoU field_info;
    list_t<type_t>          targs;
  };

  EXTERN_ABSYN tunion AggrInfoU {
    UnknownAggr(aggr_kind_t,typedef_name_t);
    KnownAggr(aggrdecl_t@);
  };
  EXTERN_ABSYN struct AggrInfo {
    tunion AggrInfoU aggr_info;
    list_t<type_t> targs; // actual type parameters
  };
  EXTERN_ABSYN struct ArrayInfo {
    type_t    elt_type;       // element type
    tqual_t   tq;             // qualifiers
    exp_opt_t num_elts;       // number of elements
    conref_t<bool> zero_term; // true => zero-terminated
  };

  // Note: The last fields of AggrType, TypedefType, and the decl 
  // are set by check_valid_type which most of the compiler assumes
  // has been called.  Doing so avoids the need for some code to have and use
  // a type-name environment just like variable-binding fields avoid the need
  // for some code to have a variable environment.
  // FIX: Change a lot of the abstract-syntaxes options to nullable pointers.
  //      For example, the last field of TypedefType
  // FIX: May want to make this raw_typ and store the kinds with the types.
  EXTERN_ABSYN tunion Type {
    VoidType; // MemKind
    // Evars are introduced for unification or via _ by the user.
    // The kind can get filled in during well-formedness checking.
    // The type can get filled in during unification.
    // The int is used as a unique identifier for printing messages.
    // The list of tvars is the set of free type variables that can
    // occur in the type to which the evar is constrained.  
    Evar(opt_t<kind_t>,opt_t<type_t>,int,opt_t<list_t<tvar_t>>); 
    VarType(tvar_t); // type variables, kind induced by tvar
    TunionType(tunion_info_t); // [x]tunion Foo
    TunionFieldType(tunion_field_info_t); // [x]tunion Foo.Bar
    PointerType(ptr_info_t); // t*, t?, t@, etc.  BoxKind when not Unknown_b
    IntType(sign_t,size_of_t); // char, short, int.  MemKind unless B4
    FloatType;  // MemKind
    DoubleType(bool); // MemKind.  when bool is true, long double
    ArrayType(array_info_t);// MemKind
    FnType(fn_info_t); // MemKind
    // We treat anonymous structs, unions, and enums slightly differently
    // than C.  In particular, we treat structurally equivalent types as
    // equal.  C requires a name for each type and uses by-name equivalence.
    TupleType(list_t<$(tqual_t,type_t)@>); // MemKind
    AggrType(aggr_info_t); // MemKind (named structs and unions)
    AnonAggrType(aggr_kind_t,list_t<aggrfield_t>); // MemKind
    EnumType(typedef_name_t,struct Enumdecl *); // MemKind
    AnonEnumType(list_t<enumfield_t>); // MemKind
    SizeofType(type_t); // AnyKind -> BoxKind
    RgnHandleType(type_t);   // a handle for allocating in a region.  BoxKind
    // An abbreviation -- the type_t* contains the definition iff any
    TypedefType(typedef_name_t,list_t<type_t>,struct Typedefdecl *,type_t*);
    TagType(type_t);         // tag_t<t>.  IntKind -> BoxKind.
    TypeInt(int);            // `i, i a const int.  IntKind
    HeapRgn;                 // The heap region.  RgnKind 
    AccessEff(type_t);       // Uses region r.  RgnKind -> EffKind
    JoinEff(list_t<type_t>); // e1+e2.  EffKind list -> EffKind
    RgnsEff(type_t);         // regions(t).  AnyKind -> EffKind
  };

  // used when parsing/pretty-printing function definitions.
  EXTERN_ABSYN tunion Funcparams {
    NoTypes(list_t<var_t>,seg_t); // K&R style.  
    WithTypes(list_t<$(opt_t<var_t>,tqual_t,type_t)@>, // args and types
              bool,                                    // true ==> c_varargs
              vararg_info_t *,                         // cyc_varargs
              opt_t<type_t>,                           // effect
              list_t<$(type_t,type_t)@>);              // region partial order
  };

  // Used in attributes below.
  EXTERN_ABSYN tunion Format_Type { Printf_ft, Scanf_ft };

  // GCC attributes that we currently try to support:  this definition
  // is only used for parsing and pretty-printing.  See GCC info pages
  // for details.
  EXTERN_ABSYN tunion Attribute {
    Regparm_att(int); 
    Stdcall_att;      
    Cdecl_att;        
    Fastcall_att;
    Noreturn_att;     
    Const_att;
    Aligned_att(int);
    Packed_att;
    Section_att(string_t);
    Nocommon_att;
    Shared_att;
    Unused_att;
    Weak_att;
    Dllimport_att;
    Dllexport_att;
    No_instrument_function_att;
    Constructor_att;
    Destructor_att;
    No_check_memory_usage_att;
    Format_att(tunion Format_Type, 
               int,   // format string arg
               int);  // first arg to type-check
    Initializes_att(int); // param that function initializes through
    Pure_att;
  };

  // Type modifiers are used for parsing/pretty-printing
  EXTERN_ABSYN tunion Type_modifier {
    Carray_mod(conref_t<bool>); // [], conref controls zero-term
    ConstArray_mod(exp_t,conref_t<bool>); // [c], conref controls zero-term
    Pointer_mod(ptr_atts_t,tqual_t); // qualifer for the point (**not** elts)
    Function_mod(funcparams_t);
    TypeParams_mod(list_t<tvar_t>,seg_t,bool);// when bool is true, print kinds
    Attributes_mod(seg_t,attributes_t);
  };

  // Constants
  EXTERN_ABSYN tunion Cnst {
    Char_c(sign_t,char);          // chars
    Short_c(sign_t,short);        // shorts
    Int_c(sign_t,int);            // ints
    LongLong_c(sign_t,long long); // long-longs
    Float_c(string_t);            // floats -- where's doubles?
    String_c(string_t);           // strings
    Null_c;                       // NULL
  };

  // Primitive operations
  EXTERN_ABSYN tunion Primop {
    Plus, Times, Minus, Div, Mod, Eq, Neq, Gt, Lt, Gte, Lte, Not,
    Bitnot, Bitand, Bitor, Bitxor, Bitlshift, Bitlrshift, Bitarshift,
    Size
  };

  // ++x, x++, --x, x-- respectively
  EXTERN_ABSYN tunion Incrementor { PreInc, PostInc, PreDec, PostDec };

  // information about a call to a vararg function
  EXTERN_ABSYN struct VarargCallInfo {
    int                   num_varargs;
    list_t<tunionfield_t> injectors;
    vararg_info_t        @vai;
  };

  // information for offsetof
  EXTERN_ABSYN tunion OffsetofField {
    StructField(field_name_t);
    TupleIndex(unsigned int);
  };

  // information for malloc:
  //  it's important to note that when is_calloc is false (i.e., we have
  //  a malloc or rmalloc) then we can be in one of two states depending
  //  upon whether we've only parsed the expression or type-checked it.
  //  If we've parsed it, then elt_type will be NULL and num_elts will
  //  be the entire argument to malloc.  After type-checking, the malloc
  //  argument is sizeof(*elt_type)*num_elts.
  EXTERN_ABSYN struct MallocInfo {
    bool       is_calloc; // determines whether this is a malloc or calloc
    exp_opt_t  rgn;      // only here for rmalloc and rcalloc
    type_t    *elt_type; // when [r]malloc, set by type-checker.  when 
                         // [r]calloc, set by parser
    exp_t      num_elts; // for [r]malloc: before tc, is the sizeof(t)*n.
                         //                after tc, is just n.
                         // for [r]calloc: is just n.
    bool       fat_result; // true when result is a elt_type? -- set by tc
  };

  // "raw" expressions -- don't include location info or type
  EXTERN_ABSYN tunion Raw_exp {
    Const_e(cnst_t); // constants
    Var_e(qvar_t,binding_t); // variables -- binding_t gets filled in
    UnknownId_e(qvar_t);     // used only during parsing
    Primop_e(primop_t,list_t<exp_t>); // application of primitive
    AssignOp_e(exp_t,opt_t<primop_t>,exp_t); // e1 = e2, e1 += e2, etc.
    Increment_e(exp_t,incrementor_t);  // e++, ++e, --e, e--
    Conditional_e(exp_t,exp_t,exp_t);  // e1 ? e2 : e3
    SeqExp_e(exp_t,exp_t);             // e1, e2
    UnknownCall_e(exp_t,list_t<exp_t>); // used during parsing
    // the vararg_call_info_t is non-null only if this is a vararg call
    // and is set during type-checking and used only for code generation.
    FnCall_e(exp_t,list_t<exp_t>,vararg_call_info_t *); //fn call
    Throw_e(exp_t); // throw
    NoInstantiate_e(exp_t); // e@<>
    Instantiate_e(exp_t,list_t<type_t>); // instantiation of polymorphic defn
    Cast_e(type_t,exp_t); // (t)e
    Address_e(exp_t); // &e
    New_e(exp_opt_t, exp_t); // first expression is region -- null is heap
    Sizeoftyp_e(type_t); // sizeof(t)
    Sizeofexp_e(exp_t); // sizeof(e)
    Offsetof_e(type_t,offsetof_field_t); // offsetof(t,e)
    Gentyp_e(list_t<tvar_t>, type_t); // type-rep stuff
    Deref_e(exp_t); // *e
    AggrMember_e(exp_t,field_name_t);
    AggrArrow_e(exp_t,field_name_t);
    Subscript_e(exp_t,exp_t); // e1[e2]
    Tuple_e(list_t<exp_t>); // $(e1,...,en)
    CompoundLit_e($(opt_t<var_t>,tqual_t,type_t)@,
                  list_t<$(list_t<designator_t>,exp_t)@>); 
    Array_e(list_t<$(list_t<designator_t>,exp_t)@>); // {.0=e1,...,.n=en}
    // {for i < e1 : e2} -- the bool tells us whether it's zero-terminated
    Comprehension_e(vardecl_t,exp_t,exp_t,bool); // much of vardecl is known
    // Foo{.x1=e1,...,.xn=en} (with optional witness types)
    Struct_e(typedef_name_t,
	     list_t<type_t>, // witness types, maybe fewer before type-checking
	     list_t<$(list_t<designator_t>,exp_t)@>, 
	     struct Aggrdecl *);
    // {.x1=e1,....,.xn=en}
    AnonStruct_e(type_t, list_t<$(list_t<designator_t>,exp_t)@>);
    // Foo(e1,...,en)
    Tunion_e(list_t<exp_t>,tuniondecl_t,tunionfield_t);
    Enum_e(qvar_t,struct Enumdecl *,struct Enumfield *);
    AnonEnum_e(qvar_t,type_t,struct Enumfield *);
    // malloc(e1), rmalloc(e1,e2), calloc(e1,e2), rcalloc(e1,e2,e3).  
    Malloc_e(malloc_info_t);
    // will resolve into array, struct, etc.
    UnresolvedMem_e(opt_t<typedef_name_t>,
                    list_t<$(list_t<designator_t>,exp_t)@>);
    StmtExp_e(stmt_t); // ({s;e})
    Codegen_e(fndecl_t); // code generation stuff -- not used
    Fill_e(exp_t);       // code generation stuff -- not used
  };
  // expression with auxiliary information
  EXTERN_ABSYN struct Exp {
    opt_t<type_t> topt;  // type of expression -- filled in by type-checker
    raw_exp_t     r;     // the real expression
    seg_t         loc;   // the location in the source code
    absyn_annot_t annot; // used during analysis
  };

  EXTERN_ABSYN struct ForArrayInfo {
    list_t<vardecl_t> defns;
    $(exp_t,stmt_t)   condition; // as with For_s, the statements on the 
    $(exp_t,stmt_t)   delta;     //   condition & delta are hacks to support
    stmt_t            body;      //   control-flow analysis.
  };

  // The $(exp,stmt) in loops are just a hack for holding the
  // non-local predecessors of the exp.  The stmt should always be Skip_s
  // and only the non_local_preds field is interesting.
  EXTERN_ABSYN tunion Raw_stmt {
    Skip_s;   // ;
    Exp_s(exp_t);  // e
    Seq_s(stmt_t,stmt_t); // s1;s2
    Return_s(exp_opt_t); // return; and return e;
    IfThenElse_s(exp_t,stmt_t,stmt_t); // if (e) then s1 else s2;
    While_s($(exp_t,stmt_t),stmt_t); // while (e) s;
    Break_s(stmt_opt_t);    // stmt is dest, set by type-checking
    Continue_s(stmt_opt_t); // stmt is dest, set by type-checking
    Goto_s(var_t,stmt_opt_t); // stmt is dest, set by type-checking
    For_s(exp_t,$(exp_t,stmt_t),$(exp_t,stmt_t),stmt_t); 
    Switch_s(exp_t,list_t<switch_clause_t>);  // cyclone switch 
    SwitchC_s(exp_t,list_t<switchC_clause_t>); // C switch
    // next case set by type-checking
    Fallthru_s(list_t<exp_t>,switch_clause_t *);
    Decl_s(decl_t,stmt_t); // declarations
    Cut_s(stmt_t);    // code generation stuff -- not used
    Splice_s(stmt_t); // code generation stuff -- not used
    Label_s(var_t,stmt_t); // L:s
    Do_s(stmt_t,$(exp_t,stmt_t));
    TryCatch_s(stmt_t,list_t<switch_clause_t>);
    Region_s(tvar_t, vardecl_t, bool, stmt_t); // region<`r> h {s}
    // the bool above is true when the region is resetable
    ForArray_s(forarray_info_t);
    ResetRegion_s(exp_t); // reset_region(e)
  };
  // statements with auxiliary info
  EXTERN_ABSYN struct Stmt {
    raw_stmt_t     r;               // raw statement
    seg_t          loc;             // location in source code
    list_t<stmt_t> non_local_preds; // set by type-checking, should go in the
                                    // appropriate CFStmtAnnot, not here!
    int            try_depth;       // used by code generator
    absyn_annot_t  annot;           // used by analysis
  };

  // raw patterns
  EXTERN_ABSYN tunion Raw_pat {
    Wild_p; // _ 
    Var_p(vardecl_t); // x. only name field is right until tcPat is called
    Reference_p(vardecl_t);// *p. only name field is right until tcPat is called
    TagInt_p(tvar_t,vardecl_t);// i<`i> (unpack an int)
    Tuple_p(list_t<pat_t>); // $(p1,...,pn)
    Pointer_p(pat_t); // &p
    Aggr_p(aggr_info_t,list_t<tvar_t>,list_t<$(list_t<designator_t>,pat_t)@>);
    Tunion_p(tuniondecl_t, tunionfield_t, list_t<pat_t>);
    Null_p; // NULL
    Int_p(sign_t,int); // 3
    Char_p(char);      // 'a'
    Float_p(string_t); // 3.1415
    Enum_p(enumdecl_t,enumfield_t);
    AnonEnum_p(type_t,enumfield_t);
    UnknownId_p(qvar_t); // resolved by tcpat
    UnknownCall_p(qvar_t,list_t<pat_t>); // resolved by tcpat
  };
  // patterns with auxiliary information
  EXTERN_ABSYN struct Pat {
    raw_pat_t      r;    // raw pattern
    opt_t<type_t>  topt; // type -- filled in by tcpat
    seg_t          loc;  // location in source code
  };

  // cyclone switch clauses
  EXTERN_ABSYN struct Switch_clause {
    pat_t                    pattern;  // pattern
    opt_t<list_t<vardecl_t>> pat_vars; // set by type-checker, used downstream
    exp_opt_t                where_clause; // case p && e: -- the e part
    stmt_t                   body;     // corresponding statement
    seg_t                    loc;      // location in source code
  };

  // C switch clauses
  EXTERN_ABSYN struct SwitchC_clause {
    exp_opt_t cnst_exp; // KLUDGE: null => default (parser ensures it's last)
    stmt_t    body;
    seg_t     loc;
  };

  // only local and pat cases need to worry about shadowing
  EXTERN_ABSYN tunion Binding {
    Unresolved_b;        // don't know -- error or uninitialized
    Global_b(vardecl_t); // global variable
    Funname_b(fndecl_t); // distinction between functions and function ptrs
    Param_b(vardecl_t);  // local function parameter
    Local_b(vardecl_t);  // local variable
    Pat_b(vardecl_t);    // pattern variable
  };

  // Variable declarations.
  // re-factor this so different kinds of vardecls only have what they
  // need.  Makes this a struct with an tunion componenent (Global, Pattern,
  // Param, Local)
  EXTERN_ABSYN struct Vardecl {
    scope_t            sc;          // static, extern, etc.
    qvar_t             name;        // variable name
    tqual_t            tq;          // const, volatile, etc.
    type_t             type;        // type of variable
    exp_opt_t          initializer; // optional initializer -- 
                                    // ignored for non-local/global variables
    opt_t<type_t>      rgn;         // filled in by type-checker
    // attributes can include just about anything...but the type-checker
    // must ensure that they are properly accounted for.  For instance,
    // functions cannot be aligned or packed.  And non-functions cannot
    // have regpar(n), stdcall, cdecl, noreturn, or const attributes.
    attributes_t       attributes; 
    bool               escapes;     // set by type-checker -- used for simple
    // flow analyses, means that &x is taken in some way so there can be
    // aliasing going on. (should go away since flow analysis already does
    // a less syntactic escapes analysis)
  };

  // Function declarations.
  EXTERN_ABSYN struct Fndecl {
    scope_t                    sc;         // static, extern, etc.
    bool                       is_inline;  // inline flag
    qvar_t                     name;       // function name
    list_t<tvar_t>             tvs;        // bound type variables
    opt_t<type_t>              effect;     // null => default effect
    type_t                     ret_type;   // return type
    list_t<$(var_t,tqual_t,type_t)@> args; // arguments & their quals and types
    bool                       c_varargs;   // C vararg?
    vararg_info_t*             cyc_varargs; // non-null if Cyclone vararg
    list_t<$(type_t,type_t)@>  rgn_po; // partial order on region params
    stmt_t                     body;   // body of function
    opt_t<type_t>              cached_typ; // cached type of the function
    opt_t<list_t<vardecl_t>>   param_vardecls;// so we can use pointer equality
    // any attributes except aligned or packed
    attributes_t               attributes; 
  };

  EXTERN_ABSYN struct Aggrfield {
    field_name_t   name;     // empty-string when a bitfield used for padding
    tqual_t        tq;
    type_t         type;
    exp_opt_t      width;   // bit fields: (unsigned) int and int fields only
    attributes_t   attributes; // only valid ones are aligned(i) or packed
  };

  EXTERN_ABSYN struct AggrdeclImpl {
    list_t<tvar_t>            exist_vars;
    list_t<$(type_t,type_t)@> rgn_po;
    list_t<aggrfield_t>       fields;
  };

  //for structs and tunions we should memoize the string to field-number mapping
  EXTERN_ABSYN struct Aggrdecl {
    aggr_kind_t           kind;
    scope_t               sc;  // abstract possible here
    typedef_name_t        name; // struct name
    list_t<tvar_t>        tvs;  // type parameters
    struct AggrdeclImpl * impl; // NULL when abstract
    attributes_t          attributes; 
  };

  EXTERN_ABSYN struct Tunionfield {
    qvar_t                     name; 
    list_t<$(tqual_t,type_t)@> typs;
    seg_t                      loc;
    scope_t                    sc; // relevant only for xtunions
  };

  EXTERN_ABSYN struct Tuniondecl { 
    scope_t                      sc;
    typedef_name_t               name;
    list_t<tvar_t>               tvs;
    opt_t<list_t<tunionfield_t>> fields;
    bool                         is_xtunion;
  };

  EXTERN_ABSYN struct Enumfield {
    qvar_t    name;
    exp_opt_t tag;
    seg_t     loc;
  };

  EXTERN_ABSYN struct Enumdecl {
    scope_t                    sc;
    typedef_name_t             name;
    opt_t<list_t<enumfield_t>> fields;
  };

  EXTERN_ABSYN struct Typedefdecl {
    typedef_name_t name;
    list_t<tvar_t> tvs;
    opt_t<kind_t>  kind;
    opt_t<type_t>  defn;
  };

  // raw declarations
  EXTERN_ABSYN tunion Raw_decl {
    Var_d(vardecl_t);  // variables: t x = e
    Fn_d(fndecl_t);    // functions  t f(t1 x1,...,tn xn) { ... }
    Let_d(pat_t,       // let p = e
          opt_t<list_t<vardecl_t>>, // set by type-checker, used downstream
          exp_t);
    Letv_d(list_t<vardecl_t>); // multi-let
    Aggr_d(aggrdecl_t);    // [struct|union] Foo { ... }
    Tunion_d(tuniondecl_t);    // [x]tunion Bar { ... }
    Enum_d(enumdecl_t);        // enum Baz { ... }
    Typedef_d(typedefdecl_t);  // typedef t n
    Namespace_d(var_t,list_t<decl_t>); // namespace Foo { ... }
    Using_d(qvar_t,list_t<decl_t>);  // using Foo { ... }
    ExternC_d(list_t<decl_t>); // extern "C" { ... }
  };

  // declarations w/ auxiliary info
  EXTERN_ABSYN struct Decl {
    raw_decl_t r;
    seg_t      loc;
  };

  EXTERN_ABSYN tunion Designator {
    ArrayElement(exp_t);
    FieldName(var_t);
  };

  EXTERN_ABSYN xtunion AbsynAnnot { EXTERN_ABSYN EmptyAnnot; };

  ///////////////////////////////////////////////////////////////////
  // Operations and Constructors for Abstract Syntax
  ///////////////////////////////////////////////////////////////////

  // compare variables 
  extern int qvar_cmp(qvar_t, qvar_t);
  extern int varlist_cmp(list_t<var_t>, list_t<var_t>);
  extern int tvar_cmp(tvar_t, tvar_t); // WARNING: ignores the kinds

  ///////////////////////// Namespaces ////////////////////////////
  extern tunion Nmspace.Rel_n rel_ns_null_value; // for sharing
  extern nmspace_t rel_ns_null; // for sharing
  extern bool is_qvar_qualified(qvar_t);

  ///////////////////////// Qualifiers ////////////////////////////
  extern tqual_t const_tqual();
  extern tqual_t combine_tqual(tqual_t x,tqual_t y);
  extern tqual_t empty_tqual();
  
  //////////////////////////// Constraints /////////////////////////
  extern conref_t<`a> new_conref(`a x); 
  extern conref_t<`a> empty_conref();
  extern conref_t<`a> compress_conref(conref_t<`a> x);
  extern `a conref_val(conref_t<`a> x);
  extern `a conref_def(`a, conref_t<`a> x);
  extern conref_t<bool> true_conref;
  extern conref_t<bool> false_conref;
  extern conref_t<bounds_t> bounds_one_conref;
  extern conref_t<bounds_t> bounds_unknown_conref;

  extern kindbound_t compress_kb(kindbound_t);
  extern kind_t force_kb(kindbound_t kb);
  ////////////////////////////// Types //////////////////////////////
  // return a fresh type variable of the given kind that can be unified
  // only with types whose free type variables are drawn from tenv.
  extern type_t new_evar(opt_t<kind_t,`H> k,opt_t<list_t<tvar_t,`H>,`H> tenv);
  // any memory type whose free type variables are drawn from the given list
  extern type_t wildtyp(opt_t<list_t<tvar_t,`H>,`H>);
  // unsigned types
  extern type_t char_typ, uchar_typ, ushort_typ, uint_typ, ulong_typ, ulonglong_typ;
  // signed types
  extern type_t schar_typ, sshort_typ, sint_typ, slong_typ, slonglong_typ;
  // float, double
  extern type_t float_typ, double_typ(bool);
  // empty effect
  extern type_t empty_effect;
  // exception name and type
  extern qvar_t exn_name;
  extern tuniondecl_t exn_tud;
  extern qvar_t null_pointer_exn_name;
  extern qvar_t match_exn_name;
  extern tunionfield_t null_pointer_exn_tuf;
  extern tunionfield_t match_exn_tuf;
  extern type_t exn_typ;
  // tunion PrintArg and tunion ScanfArg types
  extern qvar_t tunion_print_arg_qvar;
  extern qvar_t tunion_scanf_arg_qvar;
  // string (char ?)
  extern type_t string_typ(type_t rgn);
  extern type_t const_string_typ(type_t rgn);
  // FILE
  extern type_t file_typ();
  // pointers
  extern exp_t exp_unsigned_one; // good for sharing
  extern bounds_t bounds_one; // Upper_b(1) (good for sharing)
  // t *{e}`r
  extern type_t starb_typ(type_t t, type_t rgn, tqual_t tq, bounds_t b,
                          conref_t<bool> zero_term);
  // t @{e}`r
  extern type_t atb_typ(type_t t, type_t rgn, tqual_t tq, bounds_t b,
                        conref_t<bool> zero_term);
  // t *`r
  extern type_t star_typ(type_t t, type_t rgn, tqual_t tq, 
                         conref_t<bool> zero_term);// bounds = Upper(1)
  // t @`r
  extern type_t at_typ(type_t t, type_t rgn, tqual_t tq,
                       conref_t<bool> zero_term);  // bounds = Upper(1)
  // t*`H
  extern type_t cstar_typ(type_t t, tqual_t tq); 
  // t?`r
  extern type_t tagged_typ(type_t t, type_t rgn, tqual_t tq, 
                           conref_t<bool> zero_term);
  // void*
  extern type_t void_star_typ();
  // structs
  extern type_t strct(var_t  name);
  extern type_t strctq(qvar_t name);
  extern type_t unionq_typ(qvar_t name);
  // unions
  extern type_t union_typ(var_t name);
  // arrays
  extern type_t array_typ(type_t elt_type, tqual_t tq, exp_opt_t num_elts, 
                          conref_t<bool> zero_term);

  /////////////////////////////// Expressions ////////////////////////
  extern exp_t new_exp(raw_exp_t, seg_t);
  extern exp_t New_exp(exp_opt_t rgn_handle, exp_t, seg_t); // New_e
  extern exp_t copy_exp(exp_t);
  extern exp_t const_exp(cnst_t, seg_t);
  extern exp_t null_exp(seg_t);
  extern exp_t bool_exp(bool, seg_t);
  extern exp_t true_exp(seg_t);
  extern exp_t false_exp(seg_t);
  extern exp_t int_exp(sign_t,int,seg_t);
  extern exp_t signed_int_exp(int, seg_t);
  extern exp_t uint_exp(unsigned int, seg_t);
  extern exp_t char_exp(char c, seg_t);
  extern exp_t float_exp(string_t<`H> f, seg_t);
  extern exp_t string_exp(string_t<`H> s, seg_t);
  extern exp_t var_exp(qvar_t, seg_t);
  extern exp_t varb_exp(qvar_t, binding_t, seg_t);
  extern exp_t unknownid_exp(qvar_t, seg_t);
  extern exp_t primop_exp(primop_t, list_t<exp_t,`H> es, seg_t);
  extern exp_t prim1_exp(primop_t, exp_t, seg_t);
  extern exp_t prim2_exp(primop_t, exp_t, exp_t, seg_t);
  extern exp_t add_exp(exp_t, exp_t, seg_t);
  extern exp_t times_exp(exp_t, exp_t, seg_t);
  extern exp_t divide_exp(exp_t, exp_t, seg_t);
  extern exp_t eq_exp(exp_t, exp_t, seg_t);
  extern exp_t neq_exp(exp_t, exp_t, seg_t);
  extern exp_t gt_exp(exp_t, exp_t, seg_t);
  extern exp_t lt_exp(exp_t, exp_t, seg_t);
  extern exp_t gte_exp(exp_t, exp_t, seg_t);
  extern exp_t lte_exp(exp_t, exp_t, seg_t);
  extern exp_t assignop_exp(exp_t, opt_t<primop_t,`H>, exp_t, seg_t);
  extern exp_t assign_exp(exp_t, exp_t, seg_t);
  extern exp_t increment_exp(exp_t, incrementor_t, seg_t);
  extern exp_t post_inc_exp(exp_t, seg_t);
  extern exp_t post_dec_exp(exp_t, seg_t);
  extern exp_t pre_inc_exp(exp_t, seg_t);
  extern exp_t pre_dec_exp(exp_t, seg_t);
  extern exp_t conditional_exp(exp_t, exp_t, exp_t, seg_t);
  extern exp_t and_exp(exp_t, exp_t, seg_t); // &&
  extern exp_t or_exp(exp_t, exp_t, seg_t);  // ||
  extern exp_t seq_exp(exp_t, exp_t, seg_t);
  extern exp_t unknowncall_exp(exp_t, list_t<exp_t,`H>, seg_t);
  extern exp_t fncall_exp(exp_t, list_t<exp_t,`H>, seg_t);
  extern exp_t throw_exp(exp_t, seg_t);
  extern exp_t noinstantiate_exp(exp_t, seg_t);
  extern exp_t instantiate_exp(exp_t, list_t<type_t,`H>, seg_t);
  extern exp_t cast_exp(type_t, exp_t, seg_t);
  extern exp_t address_exp(exp_t, seg_t);
  extern exp_t sizeoftyp_exp(type_t t, seg_t);
  extern exp_t sizeofexp_exp(exp_t e, seg_t);
  extern exp_t offsetof_exp(type_t, offsetof_field_t, seg_t);
  extern exp_t gentyp_exp(list_t<tvar_t,`H>,type_t, seg_t);
  extern exp_t deref_exp(exp_t, seg_t);
  extern exp_t aggrmember_exp(exp_t, field_name_t, seg_t);
  extern exp_t aggrarrow_exp(exp_t, field_name_t, seg_t);
  extern exp_t subscript_exp(exp_t, exp_t, seg_t);
  extern exp_t tuple_exp(list_t<exp_t,`H>, seg_t);
  extern exp_t stmt_exp(stmt_t, seg_t);
  extern exp_t null_pointer_exn_exp(seg_t);
  extern exp_t match_exn_exp(seg_t);
  extern exp_t array_exp(list_t<exp_t,`H>, seg_t);
  extern exp_t unresolvedmem_exp(opt_t<typedef_name_t,`H>,
                                 list_t<$(list_t<designator_t,`H>,exp_t)@`H,`H>,
				 seg_t);
  /////////////////////////// Statements ///////////////////////////////
  extern stmt_t new_stmt(raw_stmt_t s, seg_t loc);
  extern stmt_t skip_stmt(seg_t loc);
  extern stmt_t exp_stmt(exp_t e, seg_t loc);
  extern stmt_t seq_stmt(stmt_t s1, stmt_t s2, seg_t loc);
  extern stmt_t seq_stmts(list_t<stmt_t>, seg_t loc);
  extern stmt_t return_stmt(exp_opt_t e,seg_t loc);
  extern stmt_t ifthenelse_stmt(exp_t e,stmt_t s1,stmt_t s2,seg_t loc);
  extern stmt_t while_stmt(exp_t e,stmt_t s,seg_t loc);
  extern stmt_t break_stmt(seg_t loc);
  extern stmt_t continue_stmt(seg_t loc);
  extern stmt_t for_stmt(exp_t e1,exp_t e2,exp_t e3,stmt_t s, seg_t loc);
  extern stmt_t switch_stmt(exp_t e, list_t<switch_clause_t,`H>, seg_t loc);
  extern stmt_t fallthru_stmt(list_t<exp_t,`H> el, seg_t loc);
  extern stmt_t decl_stmt(decl_t d, stmt_t s, seg_t loc); 
  extern stmt_t declare_stmt(qvar_t,type_t,exp_opt_t init,stmt_t,seg_t loc);
  extern stmt_t cut_stmt(stmt_t s, seg_t loc);
  extern stmt_t splice_stmt(stmt_t s, seg_t loc);
  extern stmt_t label_stmt(var_t v, stmt_t s, seg_t loc);
  extern stmt_t do_stmt(stmt_t s, exp_t e, seg_t loc);
  extern stmt_t goto_stmt(var_t lab, seg_t loc);
  extern stmt_t assign_stmt(exp_t e1, exp_t e2, seg_t loc);
  extern stmt_t trycatch_stmt(stmt_t,list_t<switch_clause_t,`H>,seg_t);
  extern stmt_t forarray_stmt(list_t<vardecl_t,`H>,exp_t,exp_t,stmt_t,seg_t);

  /////////////////////////// Patterns //////////////////////////////
  extern pat_t new_pat(raw_pat_t p, seg_t s);

  ////////////////////////// Declarations ///////////////////////////
  extern decl_t new_decl(raw_decl_t r, seg_t loc);
  extern decl_t let_decl(pat_t p, exp_t e, seg_t loc);
  extern decl_t letv_decl(list_t<vardecl_t,`H>, seg_t loc);
  extern vardecl_t new_vardecl(qvar_t x, type_t t, exp_opt_t init);
  extern vardecl_t static_vardecl(qvar_t x, type_t t, exp_opt_t init);
  extern struct AggrdeclImpl @ aggrdecl_impl(list_t<tvar_t,`H> exists,
					     list_t<$(type_t,type_t)@`H,`H> po,
					     list_t<aggrfield_t,`H> fs);
  extern decl_t aggr_decl(aggr_kind_t k, scope_t s, typedef_name_t n,
			  list_t<tvar_t,`H> ts, struct AggrdeclImpl *`H i,
			  attributes_t atts, seg_t loc);
  extern decl_t struct_decl(scope_t s, typedef_name_t n,
			    list_t<tvar_t,`H> ts, struct AggrdeclImpl *`H i,
                            attributes_t atts, seg_t loc);
  extern decl_t union_decl(scope_t s,typedef_name_t n,
			   list_t<tvar_t,`H> ts, struct AggrdeclImpl *`H i,
			   attributes_t atts, seg_t loc);
  extern decl_t tunion_decl(scope_t s, typedef_name_t n, list_t<tvar_t,`H> ts,
                            opt_t<list_t<tunionfield_t,`H>,`H> fs, 
                            bool is_xtunion,
			    seg_t loc);

  extern type_t function_typ(list_t<tvar_t,`H> tvs,opt_t<type_t,`H> eff_typ,
                             type_t ret_typ, 
                             list_t<$(opt_t<var_t,`H>,tqual_t,type_t)@`H,`H> args,
                             bool c_varargs, vararg_info_t *`H cyc_varargs,
                             list_t<$(type_t,type_t)@`H,`H> rgn_po,
                             attributes_t atts);
  // turn t[] into t? as appropriate
  extern type_t pointer_expand(type_t);
  // returns true when the expression is a valid left-hand-side
  extern bool is_lvalue(exp_t);

  // find a field by name from a list of fields
  extern struct Aggrfield *lookup_field(list_t<aggrfield_t>,var_t);
  // find a struct or union field by name from a declaration
  extern struct Aggrfield *lookup_decl_field(aggrdecl_t,var_t);
  // find a tuple field form a list of qualifiers and types
  extern $(tqual_t,type_t)*lookup_tuple_field(list_t<$(tqual_t,type_t)@`H>,int);
  // turn an attribute into a string
  extern string_t attribute2string(attribute_t);
  // returns true when a is an attribute for function types
  extern bool fntype_att(attribute_t a);
  // int to field-name caching used by control-flow and toc
  extern field_name_t fieldname(int);
  // get the name and aggr_kind of an aggregate type
  extern $(aggr_kind_t,qvar_t) aggr_kinded_name(tunion AggrInfoU);
  // given a checked type, get the decl
  extern aggrdecl_t get_known_aggrdecl(tunion AggrInfoU info);
  // is a type a union-type (anonymous or otherwise)
  extern bool is_union_type(type_t);

  // for testing typerep; temporary
  extern void print_decls(list_t<decl_t>);
  }

#endif
