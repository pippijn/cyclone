// parse.y:  Copyright (c) 2000, Greg Morrisett & Trevor Jim,
// all rights reserved.
//
// An adaptation of the OSI C grammar for Cyclone.  This grammar
// is adapted from the proposed C9X standard, but the productions are
// arranged as in Kernighan and Ritchie's "The C Programming
// Language (ANSI C)", Second Edition, pages 234-239.
//
// The grammar has 1 shift-reduce conflict, due to the "dangling else"
// problem, which is properly resolved by the Cyclone port of Bison. 

%{
#define YYDEBUG 0 // 1 to debug, 0 otherwise
#define YYPRINT yyprint
#define YYERROR_VERBOSE

#if YYDEBUG==1
extern xenum YYSTYPE;
extern void yyprint(int i, xenum YYSTYPE v);
#endif


#include "core.h"
#include "stdio.h"
#include "lexing.h"
#include "list.h"
#include "string.h"
#include "set.h"
#include "position.h"
#include "absyn.h"
#include "pp.h"
using Core;
using Stdio;
using Lexing;
using List;
using Absyn;
using Position;
using String;

// Typedef processing must be split between the parser and lexer.
// These functions are called by the parser to communicate typedefs
// to the lexer, so that the lexer can distinguish typedef names from
// identifiers. 
namespace Lex {
  extern void register_typedef(qvar s);
  extern void enter_namespace(var);
  extern void leave_namespace();
  extern void enter_using(qvar);
  extern void leave_using();
}

#define LOC(s,e) Position::segment_of_abs(s.first_line,e.last_line)
#define DUMMYLOC null

namespace Parse {

// Type definitions only needed during parsing. 

enum Struct_or_union { Struct_su, Union_su; };
typedef enum Struct_or_union struct_or_union_t;

enum Blockitem {
  TopDecls_bl(list_t<decl>);
  Stmt_bl(stmt);
  FnDecl_bl(fndecl);
};
typedef enum Blockitem blockitem_t;

enum Type_specifier {
  Signed_spec(seg_t);
  Unsigned_spec(seg_t);
  Short_spec(seg_t);
  Long_spec(seg_t);
  Type_spec(typ,seg_t);    // int, `a, list_t<`a>, etc. 
  Decl_spec(decl);
};
typedef enum Type_specifier type_specifier_t;

enum Storage_class {
  Typedef_sc, Extern_sc, ExternC_sc, Static_sc, Auto_sc, 
  Register_sc, Abstract_sc;
};
typedef enum Storage_class storage_class_t;

struct Declaration_spec {
  opt_t<storage_class_t>   sc;
  tqual                    tq;
  list_t<type_specifier_t> type_specs;
  bool                     is_inline;
  list_t<attribute_t>      attributes;
};
typedef struct Declaration_spec @decl_spec_t;

struct Declarator {
  qvar                  id;
  list_t<type_modifier> tms;
};
typedef struct Declarator @declarator_t;

struct Abstractdeclarator {
  list_t<type_modifier> tms;
};
typedef struct Abstractdeclarator @abstractdeclarator_t;

// forward references
static $(var,tqual,typ)@ fnargspec_to_arg(seg_t loc,
					  $(opt_t<var>,tqual,typ)@ t);
static $(typ,opt_t<decl>) 
  collapse_type_specifiers(list_t<type_specifier_t> ts, seg_t loc);
static $(tqual,typ,list_t<tvar>,list_t<attribute_t>) 
  apply_tms(tqual,typ,list_t<attribute_t>,list_t<type_modifier>);
static decl v_typ_to_typedef(seg_t loc, $(qvar,tqual,typ,list_t<tvar>,
                                          list_t<attribute_t>)@ t);

// global state (we're not re-entrant)
opt_t<Lexbuf<Function_lexbuf_state<FILE@>>> lbuf = null;
static list_t<decl> parse_result = null;

// Definitions and Helper Functions

// Error functions 
static void err(string msg, seg_t sg) {
  post_error(mk_err_parse(sg,msg));
}
static `a abort(string msg,seg_t sg) {
  err(msg,sg);
  throw Exit;
}
static void warn(string msg,seg_t sg) {
  fprintf(stderr,"%s: Warning: %s\n",string_of_segment(sg),msg);
  return;
}
static `a unimp(string msg,seg_t sg) {
  return abort(xprintf("%s unimplemented",msg),sg);
}
static void unimp2(string msg,seg_t sg) {
  fprintf(stderr,"%s: Warning: Cyclone does not yet support %s\n",
	  string_of_segment(sg),msg);
  return;
}

// Functions for creating abstract syntax 
static structfield_t 
make_struct_field(seg_t loc,
                  $(qvar,tqual,typ,list_t<tvar>,list_t<attribute_t>)@ field) {
  if ((*field)[3] != null)
    err("bad type params in struct field",loc);
  let qid = (*field)[0];
  switch ((*qid)[0]) {
  case Rel_n(null): break;
  case Abs_n(null): break;
  case Loc_n: break;
  default:
    err("struct field cannot be qualified with a module name",loc);    
    break;
  }
  let atts = (*field)[4];
  return &Structfield{.name = (*qid)[1], .tq = (*field)[1], 
                         .type = (*field)[2], .attributes = atts};
}

static $(opt_t<var>,tqual,typ)@ 
make_param(seg_t loc, $(opt_t<qvar>,tqual,typ,list_t<tvar>)@ field){
  let &$(qv_opt,tq,t,tvs) = field;
  let idopt = null;
  if (qv_opt != null) {
    idopt = &Opt((*qv_opt->v)[1]);
    switch ((*qv_opt->v)[0]) {
    case Rel_n(null): break;
    case Abs_n(null): break;
    case Loc_n: break;
    default:
      err("parameter cannot be qualified with a module name",loc);
      break;
    }
  }
  if (tvs != null)
    abort("parameter should have no type parameters",loc);
  return &$(idopt,tq,t);
}

static type_specifier_t type_spec(typ t,seg_t loc) {
  return Type_spec(t,loc);
}

// convert any array types to pointer types 
static typ array2ptr(typ t) {
  switch (t) {
  case ArrayType(t1,tq,e):
    return starb_typ(t1,HeapRgn,tq,Upper_b(e));
  default: return t;
  }
}

// convert an argument's type from arrays to pointers 
static void arg_array2ptr($(opt_t<var>,tqual,typ) @x) {
  (*x)[2] = array2ptr((*x)[2]);
}

// given an optional variable, tqual, type, and list of type
// variables, return the tqual and type and check that the type
// variables are null -- used when we have a tuple type specification. 
static $(tqual,typ)@ get_tqual_typ(seg_t loc,$(opt_t<var>,tqual,typ) @t) {
  return &$((*t)[1],(*t)[2]);
}

static void only_vardecl(list_t<stringptr> params,decl x) {
  string decl_kind;
  switch (x->r) {
  case Var_d(vd):
    if (vd->initializer != null)
      abort("initializers are not allowed in parameter declarations",x->loc);
    switch ((*vd->name)[0]) {
    case Loc_n: break;
    case Rel_n(null): break;
    case Abs_n(null): break;
    default:
      err("module names not allowed on parameter declarations",x->loc);
      break;
    }
    // for sanity-checking of old-style parameter declarations
    bool found = false;
    for(; params != null; params = params->tl)
      if(zstrptrcmp((*vd->name)[1], params->hd)==0) {
	found = true;
	break;
      }
    if (!found)
      abort(xprintf("%s is not listed as a parameter",
		    *((*vd->name)[1])),x->loc);
    return;
  case Let_d(_,_,_,_,_): decl_kind = "let declaration";        break;
  case Fn_d(_):          decl_kind = "function declaration";   break;
  case Struct_d(_):      decl_kind = "struct declaration";     break;
  case Union_d:          decl_kind = "union declaration";      break;
  case Enum_d(_):        decl_kind = "enum declaration";       break;
  case Typedef_d(_):     decl_kind = "typedef";                break;
  case Xenum_d(_):       decl_kind = "xenum declaration";      break;
  case Namespace_d(_,_): decl_kind = "namespace declaration";  break;
  case Using_d(_,_):     decl_kind = "using declaration";      break;
  case ExternC_d(_):     decl_kind = "extern C declaration";   break;
  }
  abort(xprintf("%s appears in parameter type", decl_kind), x->loc);
  return;
}

// For old-style function definitions,
// get a parameter type from a list of declarations
static $(opt_t<var>,tqual,typ)@ get_param_type($(list_t<decl>,seg_t)@ env,
					       stringptr x) {
  let &$(tdl,loc) = env;
  if (tdl==null)
    return(abort(xprintf("missing type for parameter %s",*x),loc));
  switch (tdl->hd->r) {
  case Var_d(vd):
    switch ((*vd->name)[0]) {
    case Loc_n: break;
    case Rel_n(null): break;
    case Abs_n(null): break;
    default:
      err("module name not allowed on parameter",loc);
      break;
    }
    if (zstrptrcmp((*vd->name)[1],x)==0)
      return new {$(new{Opt((*vd->name)[1])},vd->tq,vd->type)};
    else 
      return get_param_type(&$(tdl->tl,loc),x);
  default:
    // This should never happen, because we use only_vardecl first
    return(abort("non-variable declaration",tdl->hd->loc));
  }
}

static bool is_typeparam(type_modifier tm) {
  switch (tm) {
  case TypeParams_mod(_,_,_): return true;
  default: return false;
  }
}

// convert an identifier to a type -- if it's the special identifier
// `H then return HeapRgn, otherwise, return a type variable.  
static typ id2type(string s, conref<kind_t> k) {
  if (zstrcmp(s,"`H") == 0)
    return HeapRgn;
  else 
    return VarType(&Tvar(new {s},k));
}

// convert a list of types to a list of typevars -- the parser can't
// tell lists of types apart from lists of typevars easily so we parse
// them as types and then convert them back to typevars.  See
// productions "struct_or_union_specifier" and "enum_specifier"; 
static tvar typ2tvar(seg_t loc, typ t) {
  switch (t) {
  case VarType(pr): return pr;
  default: return abort("expecting a list of type variables, not types",loc);
  }
}
static typ tvar2typ(tvar pr) {
  return VarType(pr);
}

// Convert an old-style function into a new-style function
static list_t<type_modifier> oldstyle2newstyle(list_t<type_modifier> tms, 
                                               list_t<decl> tds, seg_t loc) {
  // Not an old-style function
  if (tds==null) return tms;

  // If no function is found, or the function is not innermost, then
  // this is not a function definition; it is an error.  But, we
  // return silently.  The error will be caught by make_function below.
  if (tms==null) return null;

  switch (tms->hd) {
    case Function_mod(args): {
      // Is this the innermost function??
      if (tms->tl==null ||
          (is_typeparam(tms->tl->hd) && tms->tl->tl==null)) {
        // Yes
        switch (args) {
        case WithTypes(_,_,_):
          warn("function declaration with both new- and old-style parameter"
	       "declarations; ignoring old-style",loc);
          return tms;
        case NoTypes(ids,_):
          List::iter_c(only_vardecl,ids,tds);
          let env = &$(tds,loc);
          return
            &List(Function_mod(WithTypes(List::map_c(get_param_type,env,ids),
					 false,null)),null);
        }
      } else
        // No, keep looking for the innermost function
        return &List(tms->hd,oldstyle2newstyle(tms->tl,tds,loc));
    }
    default: return &List(tms->hd,oldstyle2newstyle(tms->tl,tds,loc));
  }
}

// make a top-level function declaration out of a declaration-specifier 
// (return type, etc.), a declarator (the function name and args),
// a declaration list (for old-style function definitions), and a statement.
static fndecl make_function(opt_t<decl_spec_t> dso, declarator_t d,
			    list_t<decl> tds, stmt body, seg_t loc) {
  // Handle old-style parameter declarations
  if (tds!=null) 
    d = &Declarator(d->id,oldstyle2newstyle(d->tms,tds,loc));

  scope sc = Public;
  list_t<type_specifier_t> tss = null;
  tqual tq = empty_tqual();
  bool is_inline = false;
  list_t<attribute_t> atts = null;

  if (dso != null) {
    tss = dso->v->type_specs;
    tq  = dso->v->tq;
    is_inline = dso->v->is_inline;
    atts = dso->v->attributes;
    // Examine storage class; like C, we allow both static and extern 
    if (dso->v->sc != null)
      switch (dso->v->sc->v) {
      case Extern_sc: sc = Extern; break;
      case ExternC_sc: sc = ExternC; break;
      case Static_sc: sc = Static; break;
      default: err("bad storage class on function",loc); break;
      }
  }
  let $(t,decl_opt) = collapse_type_specifiers(tss,loc);
  let $(fn_tqual,fn_type,x,out_atts) = apply_tms(tq,t,atts,d->tms);
  // what to do with the left-over attributes out_atts?  I'm just
  // going to append them to the function declaration and let the
  // type-checker deal with it.
  if (decl_opt != null)
    warn("nested type declaration within function prototype",loc);
  if (x != null)
    // Example:   `a f<`b><`a>(`a x) {...}
    // Here info[2] will be the list `b.
    warn("bad type params, ignoring",loc);
  // fn_type had better be a FnType
  switch (fn_type) {
    case FnType(FnInfo{tvs,eff,ret_type,args,varargs,attributes}):
      let args2 = List::map_c(fnargspec_to_arg,loc,args);
      // We don't fill in the cached type here because we may need
      // to figure out the bound type variables and the effect.  
      return &Fndecl {.sc=sc,.name=d->id,.tvs=tvs,
                         .is_inline=is_inline,.effect=eff,
                         .ret_type=ret_type,.args=args2,
                         .varargs=varargs,.body=body,.cached_typ=null,
                         .param_vardecls=null,
                         .attributes = append(attributes,out_atts)};
    default:
      return abort("declarator is not a function prototype",loc);
  }
}

static $(var,tqual,typ)@ fnargspec_to_arg(seg_t loc,
					  $(opt_t<var>,tqual,typ)@ t) {
  if ((*t)[0] == null) {
    err("missing argument variable in function prototype",loc);
    return &$(new{"?"},(*t)[1],(*t)[2]);
  } else
    return &$((*t)[0]->v,(*t)[1],(*t)[2]);
}

// Given a type-specifier list, determines the type and any declared
// structs, unions, or enums.  Most of this is just collapsing
// combinations of [un]signed, short, long, int, char, etc.  We're
// probably more permissive than is strictly legal here.  For
// instance, one can write "unsigned const int" instead of "const
// unsigned int" and so forth.  I don't think anyone will care...
// (famous last words.) 
static string msg1 = "at most one type may appear within a type specifier";
static string msg2 = 
  "const or volatile may appear only once within a type specifier";
static string msg3 = "type specifier includes more than one declaration";
static string msg4 = 
  "sign specifier may appear only once within a type specifier";

static $(typ,opt_t<decl>) 
  collapse_type_specifiers(list_t<type_specifier_t> ts, seg_t loc) {

  opt_t<decl> declopt = null;    // any hidden declarations 

  bool      seen_type = false;
  bool      seen_sign = false;
  bool      seen_size = false;
  typ       t         = VoidType;
  size_of_t sz        = B4;
  sign_t    sgn       = Signed;

  seg_t last_loc = loc;

  for(; ts != null; ts = ts->tl)
    switch (ts->hd) {
    case Type_spec(t2,loc2):
      if(seen_type) err(msg1,loc2);
      last_loc  = loc2;
      seen_type = true;
      t         = t2;
      break;
    case Signed_spec(loc2):
      if(seen_sign) err(msg4,loc2);
      if(seen_type) err("signed qualifier must come before type",loc2);
      last_loc  = loc2;
      seen_sign = true;
      sgn       = Signed;
      break;
    case Unsigned_spec(loc2):
      if(seen_sign) err(msg4,loc2);
      if(seen_type) err("signed qualifier must come before type",loc2);
      last_loc  = loc2;
      seen_sign = true;
      sgn       = Unsigned;
      break;
    case Short_spec(loc2):
      if(seen_size)
        err("integral size may appear only once within a type specifier",loc2);
      if(seen_type) err("short modifier must come before base type",loc2);
      last_loc  = loc2;
      seen_size = true;
      sz        = B2;
      break;
    case Long_spec(loc2):
      if(seen_type) err("long modifier must come before base type",loc2);
      // okay to have seen a size so long as it was long (means long long)
      // That happens when we've seen a size yet we're B4
      if(seen_size)
	switch (sz) {
	case B4:
	  sz = B8;
	  break;
	default: err("extra long in type specifier",loc2); break;
	}	  
      last_loc = loc2;
      // the rest is is necessary if it's long and harmless if long long
      seen_size = true;
      break;
    case Decl_spec(d):
      // we've got a struct or enum declaration embedded in here -- return
      // the declaration as well as a copy of the type -- this allows
      // us to declare structs as a side effect inside typedefs
      // Note: Leave the last fields null so check_valid_type knows the type
      //       has not been checked.
      last_loc = d->loc;
      if (declopt == null && !seen_type) {
	seen_type = true;
        switch (d->r) {
        case Struct_d(sd):
          let args = List::map(tvar2typ,sd->tvs);
          t = StructType(sd->name->v,args,null);
          if (sd->fields!=null) declopt = &Opt(d);
	  break;
        case Enum_d(ed):
          let args = List::map(tvar2typ,ed->tvs);
          t = EnumType(ed->name->v,args,null);
          if (ed->fields!=null) declopt = &Opt(d);
	  break;
        case Xenum_d(xed):
          t = XenumType(xed->name,null);
          if (xed->fields != null) declopt = &Opt(d);
	  break;
        case Union_d:
          // FIX: TEMPORARY SO WE CAN TEST THE PARSER
          t = UnionType;
	  break;
        default:
	  abort("bad declaration within type specifier",d->loc);
	  break;
        }
      } else err(msg3,d->loc);
      break;
    }

  // it's okay to not have an explicit type as long as we have some
  // combination of signed, unsigned, short, long, or longlong 
  if (!seen_type) {
    if(!seen_sign && !seen_size) err("missing type withing specifier",last_loc);
    t = IntType(sgn, sz);
  } else {
    if(seen_sign)
      switch (t) {
      case IntType(_,sz2): t = IntType(sgn,sz2); break;
      default: err("sign specification on non-integral type",last_loc); break;
      }
    if(seen_size)
      switch (t) {
      case IntType(sgn2,_):
	t = IntType(sgn2,sz);
	break;
      default: err("size qualifier on non-integral type",last_loc); break;
      }
  }
  return $(t, declopt);
}

static list_t<$(qvar,tqual,typ,list_t<tvar>,list_t<attribute_t>)@> 
  apply_tmss(tqual tq, typ t,list_t<declarator_t> ds,attributes_t shared_atts)
{
  if (ds==null) return null;
  let d = ds->hd;
  let q = d->id;
  let $(tq,new_typ,tvs,atts) = apply_tms(tq,t,shared_atts,d->tms);
  return &List(&$(q,tq,new_typ,tvs,atts),
               apply_tmss(tq,t,ds->tl,shared_atts));
}

static bool fn_type_att(attribute_t a) {
  switch (a) {
  case Regparm_att(_): fallthru;
  case Stdcall_att: fallthru;
  case Cdecl_att: fallthru;
  case Noreturn_att: fallthru;
  case Const_att: return true;
  default: return false;
  }
}

static $(tqual,typ,list_t<tvar>,list_t<attribute_t>) 
  apply_tms(tqual tq, typ t, list_t<attribute_t> atts,
            list_t<type_modifier> tms) {
  if (tms==null) return $(tq,t,null,atts);
  switch (tms->hd) {
    case Carray_mod:
      return apply_tms(empty_tqual(),ArrayType(t,tq,uint_exp(0,null)),
                       atts,tms->tl);
    case ConstArray_mod(e):
      return apply_tms(empty_tqual(),ArrayType(t,tq,e),atts,tms->tl);
    case Function_mod(args): {
      switch (args) {
      case WithTypes(args2,vararg,eff):
        list_t<tvar> typvars = null;
        // any function type attributes seen thus far get put in the function
        // type
        attributes_t fn_atts = null, new_atts = null;
        for (_ as = atts; as != null; as = as->tl) {
          if (fn_type_att(as->hd))
            fn_atts = &List(as->hd,fn_atts);
          else 
            new_atts = &List(as->hd,new_atts);
        }
        // functions consume type parameters
        if (tms->tl != null) {
          switch (tms->tl->hd) {
          case TypeParams_mod(ts,_,_):
            typvars = ts;
            tms=tms->tl; // skip TypeParams on call of apply_tms below
	    break;
          default:
            break;
          }
        }
        // special case where the parameters are void, e.g., int f(void)
        if (!vararg                // not vararg function
            && args2 != null      // not empty arg list
            && args2->tl == null   // not >1 arg
            && (*args2->hd)[0] == null // not f(void x)
            && (*args2->hd)[2] == VoidType) {
	  args2 = null;
	  vararg = false;
	}
	// convert result type from array to pointer result
	t = array2ptr(t);
	// convert any array arguments to pointer arguments
	List::iter(arg_array2ptr,args2);
        // Note, we throw away the tqual argument.  An example where
        // this comes up is "const int f(char c)"; it doesn't really
        // make sense to think of the function as returning a const
        // (or volatile, or restrict).  The result will be copied
        // anyway.  TODO: maybe we should issue a warning.  But right
        // now we don't have a loc so the warning will be confusing.
        return apply_tms(empty_tqual(),
			 function_typ(typvars,eff,t,args2,vararg,fn_atts),
                         new_atts,
                         tms->tl);
      case NoTypes(_,loc):
        throw abort("function declaration without parameter types",loc);
      }
    }
    case TypeParams_mod(ts,loc,_): {
      // If we are the last type modifier, this could be the list of
      // type parameters to a typedef:
      // typedef struct foo<`a,int> foo_t<`a>
      if (tms->tl==null)
        return $(tq,t,ts,atts);
      // Otherwise, it is an error in the program if we get here;
      // TypeParams should already have been consumed by an outer
      // Function (see last case).
      throw abort("type parameters must appear before function arguments "
		  "in declarator",loc);
    }
    case Pointer_mod(ps,rgntyp,tq2): {
      switch (ps) {
      case NonNullable_ps(ue):
	return apply_tms(tq2,atb_typ(t,rgntyp,tq,Upper_b(ue)),atts,tms->tl);
      case Nullable_ps(ue):
	return apply_tms(tq2,starb_typ(t,rgntyp,tq,Upper_b(ue)),atts,tms->tl);
      case TaggedArray_ps:
	return apply_tms(tq2,tagged_typ(t,rgntyp,tq),atts,tms->tl);
      }
    }
    case Attributes_mod(loc,atts2):
      // FIX: get this in line with GCC
      // attributes get attached to function types -- I doubt that this
      // is GCC's behavior but what else to do?
      return apply_tms(tq,t,List::append(atts,atts2),tms->tl);
  }
}

// given a specifier-qualifier list, warn and ignore about any nested type
// definitions and return the collapsed type.
// FIX: We should somehow deal with the nested type definitions.
typ speclist2typ(list_t<type_specifier_t> tss, seg_t loc) {
  let $(t,decls_opt) = collapse_type_specifiers(tss,loc);
  if(decls_opt != null)
    warn("ignoring nested type declaration(s) in specifier list",loc);
  return t;
}


// given a local declaration and a statement produce a decl statement 
static stmt flatten_decl(decl d,stmt s) {
  return new_stmt(Decl_s(d,s),segment_join(d->loc,s->loc));
}

// given a list of local declarations and a statement, produce a big
// decl statement.
static stmt flatten_declarations(list_t<decl> ds, stmt s){
  return List::fold_right(flatten_decl,ds,s);
}

// Given a declaration specifier list (a combination of storage class
// [typedef, extern, static, etc.] and type specifiers (signed, int,
// `a, const, etc.), and a list of declarators and initializers,
// produce a list of top-level declarations.  By far, this is the most
// involved function and thus I expect a number of subtle errors. 
static list_t<decl> make_declarations(decl_spec_t ds,
                                      list_t<$(declarator_t,exp_opt)@> ids,
                                      seg_t loc) {
  list_t<type_specifier_t> tss       = ds->type_specs;
  tqual                  tq        = ds->tq;
  bool                   istypedef = false;  // updated below if necessary
  scope                  s         = Public; // updated below if necessary
  list_t<attribute_t>    atts      = ds->attributes;

  if (ds->is_inline)
    err("inline is only allowed on function definitions",loc);
  if (tss == null) {
    err("missing type specifiers in declaration",loc);
    return null;
  }

  if (ds->sc != null)
    switch (ds->sc->v) {
    case Typedef_sc:  istypedef = true; break;
    case Extern_sc:   s = Extern;   break;
    case ExternC_sc:  s = ExternC;  break;
    case Static_sc:   s = Static;   break;
    case Auto_sc:     s = Public;   break;
    case Register_sc: s = Public;   break;
    case Abstract_sc: s = Abstract; break;
    }
 
  // separate the declarators from their initializers
  let $(declarators, exprs) = List::split(ids);
  // check to see if there are no initializers -- useful later on
  bool exps_empty = true;
  for (list_t<exp_opt> es = exprs; es != null; es = es->tl)
    if (es->hd != null) {
      exps_empty = false;
      break;
    }

  // Collapse the type specifiers to get the base type and any
  // optional nested declarations 
  let ts_info = collapse_type_specifiers(tss,loc);
  if (declarators == null) {
    // here we have a type declaration -- either a struct, union,
    // enum, or xenum as in: "struct Foo { ... };" 
    let $(t,declopt) = ts_info;
    if (declopt != null) {
      decl d = declopt->v;
      switch (d->r) {
      case Struct_d(sd): sd->sc = s; sd->attributes = atts; break;
      case Enum_d(ed)  : 
        ed->sc = s; 
        if (atts != null) err("bad attributes on enum",loc); break;
      case Xenum_d(ed) : 
        ed->sc = s; 
        if (atts != null) err("bad attributes on xenum",loc); break;
      default: err("bad declaration",loc); return null;
      }
      return &List(d,null);
    } else {
      switch (t) {
      case StructType(n,ts,_):
        let ts2 = List::map_c(typ2tvar,loc,ts);
        let sd = &Structdecl{s,&Opt((typedef_name_t)n),ts2,null,null};
        if (atts != null) err("bad attributes on struct",loc);
        return &List(&Decl(Struct_d(sd),loc),null);
      case EnumType(n,ts,_):
        let ts2 = List::map_c(typ2tvar,loc,ts);
        let ed  = enum_decl(s,&Opt((typedef_name_t)n),ts2,null,loc);
        if (atts != null) err("bad attributes on enum",loc);
        return &List(ed,null);
      case XenumType(n,_):
        let ed = &Xenumdecl{.sc=s, .name=n, .fields=null};
        if (atts != null) err("bad attributes on xenum",loc);
        return &List(&Decl(Xenum_d(ed),loc),null);
      case UnionType:
        // FIX: TEMPORARY SO WE CAN TEST THE PARSER 
        if (atts != null) err("bad attributes on union",loc);
        return &List(&Decl(Union_d,loc),null);
      default: err("missing declarator",loc); return null;
      }
    }
  } else {
    // declarators != null 
    typ t      = ts_info[0];
    let fields = apply_tmss(tq,t,declarators,atts);
    if (istypedef) {
      // we can have a nested struct, union, enum, or xenum
      // declaration within the typedef as in:
      // typedef struct Foo {...} t; 
      if (!exps_empty) 
	err("initializer in typedef declaration",loc);
      list_t<decl> decls = List::map_c(v_typ_to_typedef,loc,fields);
      if (ts_info[1] != null) {
        decl d = ts_info[1]->v;
        switch (d->r) {
        case Struct_d(sd): 
          sd->sc = s; sd->attributes = atts; atts = null; 
          break;
        case Enum_d(ed)  : ed->sc = s; break;
        case Xenum_d(ed) : ed->sc = s; break;
        default:
          err("declaration within typedef is not a struct,enum, or xenum",loc);
	  break;
        }
        decls = &List(d,decls);
      }
      if (atts != null) 
        err(xprintf("bad attribute %s in typedef",attribute2string(atts->hd)),
            loc);
      return decls;
    } else {
      // here, we have a bunch of variable declarations 
      if (ts_info[1] != null)
        unimp2("nested type declaration within declarator",loc);
      list_t<decl> decls = null;
      for (let ds = fields; ds != null; ds = ds->tl, exprs = exprs->tl) {
	let &$(x,tq2,t2,tvs2,atts2) = ds->hd;
        if (tvs2 != null)
          warn("bad type params, ignoring",loc);
        if (exprs == null)
          abort("unexpected null in parse!",loc);
        let eopt = exprs->hd;
        let vd   = new_vardecl(x, t2, eopt);
	vd->tq = tq2;
	vd->sc = s;
        vd->attributes = atts2;
        let d = &Decl(Var_d(vd),loc);
        decls = &List(d,decls);
      }
      return List::imp_rev(decls);
    }
  }
}

// Convert an identifier to a kind 
static kind_t id_to_kind(string s, seg_t loc) {
  if (strlen(s) != 1) { 
    err(xprintf("bad kind: %s",s), loc); 
    return BoxKind;
  } else {
    switch (s[0]) {
    case 'A': return AnyKind;
    case 'M': return MemKind;
    case 'B': return BoxKind;
    case 'R': return RgnKind;
    case 'E': return EffKind;
    default: 
      err(xprintf("bad kind: %s",s), loc); 
      return BoxKind;
    }
  }
}


// convert an (optional) variable, tqual, type, and type
// parameters to a typedef declaration.  As a side effect, register
// the typedef with the lexer.  
// TJ: the tqual should make it into the typedef as well,
// e.g., typedef const int CI; 
static decl v_typ_to_typedef(seg_t loc, $(qvar,tqual,typ,list_t<tvar>,list_t<attribute_t>)@ t) {
  qvar x = (*t)[0];
  // tell the lexer that x is a typedef identifier
  Lex::register_typedef(x);
  if ((*t)[4] != null)
    err(xprintf("bad attribute %s within typedef",
                attribute2string((*t)[4]->hd)),loc);
  return new_decl(Typedef_d(&Typedefdecl{.name=x, .tvs=(*t)[3], 
					 .defn=(*t)[2]}),loc);
}
} // end namespace Parse
using Parse;
%}

// ANSI C keywords 
%token AUTO REGISTER STATIC EXTERN TYPEDEF VOID CHAR SHORT INT LONG FLOAT
%token DOUBLE SIGNED UNSIGNED CONST VOLATILE RESTRICT
%token STRUCT UNION CASE DEFAULT INLINE
%token IF ELSE SWITCH WHILE DO FOR GOTO CONTINUE BREAK RETURN SIZEOF ENUM
// Cyc:  CYCLONE additional keywords 
%token NULL_kw LET THROW TRY CATCH
%token NEW ABSTRACT FALLTHRU USING NAMESPACE XENUM
%token FILL CODEGEN CUT SPLICE
%token PRINTF FPRINTF XPRINTF SCANF FSCANF SSCANF MALLOC
// double and triple-character tokens 
%token PTR_OP INC_OP DEC_OP LEFT_OP RIGHT_OP LE_OP GE_OP EQ_OP NE_OP
%token AND_OP OR_OP MUL_ASSIGN DIV_ASSIGN MOD_ASSIGN ADD_ASSIGN
%token SUB_ASSIGN LEFT_ASSIGN RIGHT_ASSIGN AND_ASSIGN
%token XOR_ASSIGN OR_ASSIGN ELLIPSIS LEFT_RIGHT
// Cyc:  added COLON_COLON double token 
%token COLON_COLON
// identifiers and constants 
%token IDENTIFIER INTEGER_CONSTANT STRING
%token CHARACTER_CONSTANT FLOATING_CONSTANT
// Cyc: type variables, qualified identifers and typedef names 
%token TYPE_VAR QUAL_IDENTIFIER QUAL_TYPEDEF_NAME
// Cyc: added __attribute__ keyword 
%token ATTRIBUTE
// the union type for all productions -- for now a placeholder 
%union {
  Okay_tok;
  Int_tok($(sign_t,int)@);
  Char_tok(char);
  Pointer_Sort_tok(enum Pointer_Sort);
  Short_tok(short);
  String_tok(string);
  Stringopt_tok(opt_t<stringptr>);
  Type_tok(typ);
  TypeList_tok(list_t<typ>);
  Exp_tok(exp);
  ExpList_tok(list_t<exp>);
  Primop_tok(primop);
  Primopopt_tok(opt_t<primop>);
  QualId_tok(qvar);
  Stmt_tok(stmt);
  SwitchClauseList_tok(list_t<switch_clause>);
  Pattern_tok(pat);
  PatternList_tok(list_t<pat>);
  FnDecl_tok(fndecl);
  DeclList_tok(list_t<decl>);
  DeclSpec_tok(decl_spec_t);
  InitDecl_tok($(declarator_t,exp_opt)@);
  InitDeclList_tok(list_t<$(declarator_t,exp_opt)@>);
  StorageClass_tok(storage_class_t);
  TypeSpecifier_tok(type_specifier_t);
  QualSpecList_tok($(tqual,list_t<type_specifier_t>,attributes_t)@);
  TypeQual_tok(tqual);
  StructFieldDeclList_tok(list_t<structfield_t>);
  StructFieldDeclListList_tok(list_t<list_t<structfield_t>>);
  Declarator_tok(declarator_t);
  DeclaratorList_tok(list_t<declarator_t>);
  AbstractDeclarator_tok(abstractdeclarator_t);
  EnumeratorField_tok(enumfield);
  EnumeratorFieldList_tok(list_t<enumfield>);
  ParamDecl_tok($(opt_t<var>,tqual,typ)@);
  ParamDeclList_tok(list_t<$(opt_t<var>,tqual,typ)@>);
  ParamDeclListBool_tok($(list_t<$(opt_t<var>,tqual,typ)@>,bool,opt_t<typ>)@);
  StructOrUnion_tok(struct_or_union_t);
  IdList_tok(list_t<var>);
  Designator_tok(designator);
  DesignatorList_tok(list_t<designator>);
  TypeModifierList_tok(list_t<type_modifier>);
  Rgn_tok(typ);
  InitializerList_tok(list_t<$(list_t<designator>,exp)@>);
  FieldPattern_tok($(list_t<designator>,pat)@);
  FieldPatternList_tok(list_t<$(list_t<designator>,pat)@>);
  BlockItem_tok(blockitem_t);
  Kind_tok(kind_t);
  Attribute_tok(attribute_t);
  AttributeList_tok(list_t<attribute_t>);
}
/* types for productions */
%type <Int_tok> INTEGER_CONSTANT
%type <String_tok> FLOATING_CONSTANT
%type <Char_tok> CHARACTER_CONSTANT
%type <Pointer_Sort_tok> pointer_char
%type <String_tok> IDENTIFIER TYPE_VAR STRING
%type <String_tok> namespace_action
%type <Exp_tok> primary_expression postfix_expression unary_expression
%type <Exp_tok> cast_expression constant multiplicative_expression
%type <Exp_tok> additive_expression shift_expression relational_expression
%type <Exp_tok> equality_expression and_expression exclusive_or_expression
%type <Exp_tok> inclusive_or_expression logical_and_expression
%type <Exp_tok> logical_or_expression conditional_expression
%type <Exp_tok> assignment_expression expression constant_expression
%type <Exp_tok> initializer
%type <ExpList_tok> argument_expression_list argument_expression_list0
%type <InitializerList_tok> initializer_list
%type <Primop_tok> unary_operator format_primop
%type <Primopopt_tok> assignment_operator
%type <QualId_tok> QUAL_IDENTIFIER QUAL_TYPEDEF_NAME qual_opt_identifier
%type <QualId_tok> using_action
%type <Stmt_tok> statement labeled_statement
%type <Stmt_tok> compound_statement block_item_list
%type <BlockItem_tok> block_item
%type <Stmt_tok> expression_statement selection_statement iteration_statement
%type <Stmt_tok> jump_statement
%type <SwitchClauseList_tok> switch_clauses
%type <Pattern_tok> pattern
%type <PatternList_tok> tuple_pattern_list tuple_pattern_list0
%type <FieldPattern_tok> field_pattern
%type <FieldPatternList_tok> field_pattern_list field_pattern_list0
%type <FnDecl_tok> function_definition function_definition2
%type <DeclList_tok> declaration declaration_list
%type <DeclList_tok> prog
%type <DeclList_tok> translation_unit translation_unit_opt external_declaration
%type <DeclSpec_tok> declaration_specifiers
%type <InitDecl_tok> init_declarator
%type <InitDeclList_tok> init_declarator_list init_declarator_list0
%type <StorageClass_tok> storage_class_specifier
%type <TypeSpecifier_tok> type_specifier
%type <TypeSpecifier_tok> struct_or_union_specifier enum_specifier
%type <StructOrUnion_tok> struct_or_union
%type <TypeQual_tok> type_qualifier type_qualifier_list
%type <StructFieldDeclList_tok> struct_declaration_list struct_declaration
%type <StructFieldDeclListList_tok> struct_declaration_list0
%type <TypeModifierList_tok> pointer
%type <Rgn_tok> rgn_opt
%type <Declarator_tok> declarator direct_declarator struct_declarator
%type <DeclaratorList_tok> struct_declarator_list struct_declarator_list0
%type <AbstractDeclarator_tok> abstract_declarator direct_abstract_declarator
%type <EnumeratorField_tok> enumerator
%type <EnumeratorFieldList_tok> enumerator_list
%type <QualSpecList_tok> specifier_qualifier_list
%type <IdList_tok> identifier_list identifier_list0
%type <ParamDecl_tok> parameter_declaration type_name
%type <ParamDeclList_tok> parameter_list
%type <ParamDeclListBool_tok> parameter_type_list
%type <TypeList_tok> type_name_list type_params_opt effect_set region_set
%type <TypeList_tok> atomic_effect
%type <DesignatorList_tok> designation designator_list
%type <Designator_tok> designator
%type <Kind_tok> kind
%type <Type_tok> any_type_name
%type <AttributeList_tok> attributes_opt attributes attribute_list
%type <Attribute_tok> attribute
/* start production */
%start prog
%%

prog:
  translation_unit
    { $$ = $!1; 
      parse_result = $1; 
    }

translation_unit:
  external_declaration
    { $$=$!1; }
| external_declaration translation_unit
    { $$=^$(List::imp_append($1,$2)); }
/* Cyc: added using and namespace */
/* NB: using_action calls Lex::enter_using */
| using_action ';' translation_unit
    { $$=^$(&List(&Decl(Using_d($1,$3),LOC(@1,@3)),null));
      Lex::leave_using();
    }
| using_action '{' translation_unit unusing_action translation_unit_opt
    { $$=^$(&List(&Decl(Using_d($1,$3),LOC(@1,@4)),$5));
    }
/* NB: namespace_action calls Lex::enter_namespace */
| namespace_action ';' translation_unit
    { $$=^$(&List(&Decl(Namespace_d(new {$1},$3),LOC(@1,@3)),null));
      Lex::leave_namespace();
    }
| namespace_action '{' translation_unit unnamespace_action translation_unit_opt
    { $$=^$(&List(&Decl(Namespace_d(new {$1},$3),LOC(@1,@4)),$5));
    }
| EXTERN STRING '{' translation_unit '}' translation_unit_opt
    { if (String::strcmp($2,"C") != 0)
        err("only extern \"C\" { ... } is allowed",LOC(@1,@2));
      $$=^$(&List(&Decl(ExternC_d($4),LOC(@1,@5)),$6));
    }
;

translation_unit_opt:
    /* empty */    { $$=^$(null); }
| translation_unit { $$=$!1; }

external_declaration:
  function_definition { $$=^$(&List(new_decl(Fn_d($1),LOC(@1,@1)),null)); }
| declaration         { $$=$!1; }
;

function_definition:
  declarator compound_statement
    { $$=^$(make_function(null,$1,null,$2,LOC(@1,@2))); }
| declaration_specifiers declarator compound_statement
    { $$=^$(make_function(&Opt($1),$2,null,$3,LOC(@1,@3))); }
| declarator declaration_list compound_statement
    { $$=^$(make_function(null,$1,$2,$3,LOC(@1,@3))); }
| declaration_specifiers declarator declaration_list compound_statement
    { $$=^$(make_function(&Opt($1),$2,$3,$4,LOC(@1,@4))); }
;

/* Used for nested functions; the optional declaration_specifiers
   would cause parser conflicts */
function_definition2:
  declaration_specifiers declarator compound_statement
    { $$=^$(make_function(&Opt($1),$2,null,$3,LOC(@1,@3))); }
| declaration_specifiers declarator declaration_list compound_statement
    { $$=^$(make_function(&Opt($1),$2,$3,$4,LOC(@1,@4))); }
;

using_action:
  USING qual_opt_identifier { Lex::enter_using($2); $$=$!2; }
;

unusing_action:
  '}' { Lex::leave_using(); }
;

namespace_action:
  NAMESPACE IDENTIFIER { Lex::enter_namespace(new {$2}); $$=$!2; }
;

unnamespace_action:
  '}' { Lex::leave_namespace(); }
;

/***************************** DECLARATIONS *****************************/
declaration:
  declaration_specifiers ';'
    { $$=^$(make_declarations($1,null,LOC(@1,@1))); }
| declaration_specifiers init_declarator_list ';'
    { $$=^$(make_declarations($1,$2,LOC(@1,@3))); }
/* Cyc:  let declaration */
| LET pattern '=' expression ';'
    { $$=^$(&List(let_decl($2,null,$4,LOC(@1,@5)),null)); }
;

declaration_list:
  declaration
    { $$=$!1; }
| declaration_list declaration
    { $$=^$(List::imp_append($1,$2)); }
;

/* Cyc: added optional attributes */
declaration_specifiers:
  storage_class_specifier attributes_opt
    { $$=^$(&Declaration_spec(&Opt($1),empty_tqual(),null,false,$2)); }
| storage_class_specifier attributes_opt declaration_specifiers
    { if ($3->sc != null)
        warn("Only one storage class is allowed in a declaration",LOC(@1,@2));
      $$=^$(&Declaration_spec(&Opt($1),$3->tq,$3->type_specs,$3->is_inline,
                              List::imp_append($2,$3->attributes)));
    }
| type_specifier attributes_opt
    { $$=^$(&Declaration_spec(null,empty_tqual(),&List($1,null),false,$2)); }
| type_specifier attributes_opt declaration_specifiers
    { $$=^$(&Declaration_spec($3->sc,$3->tq,&List($1,$3->type_specs),
                              $3->is_inline,
                              List::imp_append($2,$3->attributes))); }
| type_qualifier attributes_opt
    { $$=^$(&Declaration_spec(null,$1,null,false,$2)); }
| type_qualifier attributes_opt declaration_specifiers
    { $$=^$(&Declaration_spec($3->sc,combine_tqual($1,$3->tq),
			      $3->type_specs, $3->is_inline,
                              List::imp_append($2,$3->attributes))); }

| INLINE attributes_opt
    { $$=^$(&Declaration_spec(null,empty_tqual(),null,true,$2)); }
| INLINE attributes_opt declaration_specifiers
    { $$=^$(&Declaration_spec($3->sc,$3->tq,$3->type_specs,true,
                              List::imp_append($2,$3->attributes))); 
    }
;

storage_class_specifier:
  AUTO      { $$=^$(Auto_sc); }
| REGISTER  { $$=^$(Register_sc); }
| STATIC    { $$=^$(Static_sc); }
| EXTERN    { $$=^$(Extern_sc); }
| EXTERN STRING
  { if (strcmp($2,"C") != 0)
      err("only extern or extern \"C\" is allowed",LOC(@1,@2));
    $$ = ^$(ExternC_sc);
  } 
| TYPEDEF   { $$=^$(Typedef_sc); }
/* Cyc:  abstract specifier */
| ABSTRACT  { $$=^$(Abstract_sc); }
;

/* Cyc: added GCC attributes */
attributes_opt:
  /* empty */  { $$=^$(null); }
  | attributes { $$=$!1; }
;

attributes: 
  ATTRIBUTE '(' '(' attribute_list ')' ')'
  { $$=^$($4); }
;

attribute_list:
  attribute { $$=^$(&List($1,null)); };
| attribute ',' attribute_list { $$=^$(&List($1,$3)); }
;

attribute:
  IDENTIFIER 
  { let s = $1;
    attribute_t a;
    if (zstrcmp(s,"stdcall") == 0 || zstrcmp(s,"__stdcall__") == 0)    
      a = Stdcall_att;
    else if (zstrcmp(s,"cdecl") == 0 || zstrcmp(s,"__cdecl__") == 0) 
      a = Cdecl_att;
    else if (zstrcmp(s,"noreturn") == 0 || zstrcmp(s,"__noreturn__") == 0)
      a = Noreturn_att;
    else if (zstrcmp(s,"noreturn") == 0 || zstrcmp(s,"__noreturn__") == 0)
      a = Noreturn_att;
    else if (zstrcmp(s,"__const__") == 0)
      a = Const_att;
    else if (zstrcmp(s,"aligned") == 0 || zstrcmp(s,"__aligned__") == 0)
      a = Aligned_att(-1);
    else if (zstrcmp(s,"packed") == 0 || zstrcmp(s,"__packed__") == 0)
      a = Packed_att;
    else if (zstrcmp(s,"shared") == 0 || zstrcmp(s,"__shared__") == 0)
      a = Shared_att;
    else if (zstrcmp(s,"unused") == 0 || zstrcmp(s,"__unused__") == 0)
      a = Unused_att;
    else if (zstrcmp(s,"weak") == 0 || zstrcmp(s,"__weak__") == 0)
      a = Weak_att;
    else if (zstrcmp(s,"dllimport") == 0 || zstrcmp(s,"__dllimport__") == 0) 
      a = Dllimport_att;
    else if (zstrcmp(s,"dllexport") == 0 || zstrcmp(s,"__dllexport__") == 0)
      a = Dllexport_att;
    else if (zstrcmp(s,"no_instrument_function") == 0 || 
             zstrcmp(s,"__no_instrument_function__") == 0)
      a = No_instrument_function_att;
    else if (zstrcmp(s,"constructor") == 0 || 
             zstrcmp(s,"__constructor__") == 0)
      a = Constructor_att;
    else if (zstrcmp(s,"destructor") == 0 || zstrcmp(s,"__destructor__") == 0)
      a = Destructor_att;
    else if (zstrcmp(s,"no_check_memory_usage") == 0 || 
             zstrcmp(s,"__no_check_memory_usage__") == 0)
      a = No_check_memory_usage_att;
    else {
      err("unrecognized attribute",LOC(@1,@1));
      a = Cdecl_att;
    }
    $$=^$(a);
  }
| CONST { $$=^$(Const_att); }
| IDENTIFIER '(' INTEGER_CONSTANT ')'
  { let s = $1;
    let &$(_,n) = $3;
    attribute_t a;
    if (zstrcmp(s,"regparm") == 0 || zstrcmp(s,"__regparm__") == 0) {
      if (n <= 0 || n > 3) err("regparm requires value between 1 and 3",
                               LOC(@3,@3));
      a = Regparm_att(n);
    } else if (zstrcmp(s,"aligned") == 0 || zstrcmp(s,"__aligned__") == 0) {
      if (n < 0) err("aligned requires positive power of two",
                     LOC(@3,@3));
      unsigned int j = (unsigned int)n;
      for (; (j & 1) == 0; j = j >> 1);
      j = j >> 1;
      if (j != 0) err("aligned requires positive power of two",LOC(@3,@3));
      a = Aligned_att(n);
    }
    else {
      err("unrecognized attribute",LOC(@1,@1));
      a = Cdecl_att;
    }
    $$=^$(a);
  }
| IDENTIFIER '(' STRING ')'
  { let s = $1;
    let str = $3;
    attribute_t a;
    if (zstrcmp(s,"section") == 0 || zstrcmp(s,"__section__"))
      a = Section_att(str);
    else {
      err("unrecognized attribute",LOC(@1,@1));
      a = Cdecl_att;
    }
    $$=^$(a);
  }
;

/***************************** TYPES *****************************/
/* we could be parsing a type or a type declaration (e.g., struct)
 * so we return a type_specifier value -- either a type, a type
 * qualifier, an integral type qualifier (signed, long, etc.)
 * or a declaration.
 */
type_specifier:
  VOID      { $$=^$(type_spec(VoidType,LOC(@1,@1))); }
| '_'       { $$=^$(type_spec(new_evar(MemKind),LOC(@1,@1))); }
| CHAR      { $$=^$(type_spec(uchar_t,LOC(@1,@1))); }
| SHORT     { $$=^$(Short_spec(LOC(@1,@1))); }
| INT       { $$=^$(type_spec(sint_t,LOC(@1,@1))); }
| LONG      { $$=^$(Long_spec(LOC(@1,@1))); }
| FLOAT     { $$=^$(type_spec(float_t,LOC(@1,@1))); }
| DOUBLE    { $$=^$(type_spec(double_t,LOC(@1,@1))); }
| SIGNED    { $$=^$(Signed_spec(LOC(@1,@1))); }
| UNSIGNED  { $$=^$(Unsigned_spec(LOC(@1,@1))); }
| struct_or_union_specifier { $$=$!1; }
| enum_specifier { $$=$!1; }
/* Cyc: added type variables and optional type parameters to typedef'd names */
| TYPE_VAR 
  { $$=^$(type_spec(id2type($1,empty_conref()), LOC(@1,@1))); }
| TYPE_VAR COLON_COLON kind 
   { $$=^$(type_spec(id2type($1,new_conref($3)),LOC(@1,@3))); }
| QUAL_TYPEDEF_NAME type_params_opt
    { $$=^$(type_spec(TypedefType($1,$2,null),LOC(@1,@2))); }
/* Cyc: everything below here is an addition */
| '$' '(' parameter_list ')'
    { $$=^$(type_spec(TupleType(List::map_c(get_tqual_typ,
					    LOC(@3,@3),List::imp_rev($3))),
                      LOC(@1,@4))); }
;

/* Cyc: new */
kind:
  IDENTIFIER { $$=^$(id_to_kind($1,LOC(@1,@1))); }
| QUAL_TYPEDEF_NAME 
{ let $(nm, v) = *($1);
  if (nm != Loc_n) err("bad kind in type specifier",LOC(@1,@1));
  $$=^$(id_to_kind(*v,LOC(@1,@1)));
}
;

type_qualifier:
  CONST    { $$=^$(&Tqual(true,false,false)); }
| VOLATILE { $$=^$(&Tqual(false,true,false)); }
| RESTRICT { $$=^$(&Tqual(false,false,true)); }
;

/* parsing of struct and union specifiers. */
struct_or_union_specifier:
  struct_or_union '{' struct_declaration_list '}' 
    { decl d;
      switch ($1) {
      case Struct_su:
        d = struct_decl(Public,null,null,&Opt($3),null,LOC(@1,@4));
	break;
      case Union_su:
        unimp2("unions",LOC(@1,@4));
        d = new_decl(Union_d,LOC(@1,@4));
	break;
      }
      $$=^$(Decl_spec(d));
      unimp2("anonymous structs/unions",LOC(@1,@4));
    }
/* Cyc:  type_params_opt are added */
| struct_or_union qual_opt_identifier type_params_opt
  '{' struct_declaration_list '}' 
    { let ts = List::map_c(typ2tvar,LOC(@3,@3),$3);
      decl d;
      switch ($1) {
      case Struct_su:
        d = struct_decl(Public,&Opt($2),ts,&Opt($5),null,LOC(@1,@6));
	break;
      case Union_su:
        unimp2("unions",LOC(@1,@6));
        d = new_decl(Union_d,LOC(@1,@6));
	break;
      }
      $$=^$(Decl_spec(d));
    }
// Hack to allow struct/union names and typedef names to overlap
| struct_or_union QUAL_TYPEDEF_NAME type_params_opt
  '{' struct_declaration_list '}' 
    { let ts = List::map_c(typ2tvar,LOC(@3,@3),$3);
      decl d;
      switch ($1) {
      case Struct_su:
        d = struct_decl(Public,&Opt($2),ts,&Opt($5),null,LOC(@1,@6));
	break;
      case Union_su:
        unimp2("unions",LOC(@1,@6));
        d = new_decl(Union_d,LOC(@1,@6));
	break;
      }
      $$=^$(Decl_spec(d));
    }
/* Cyc:  type_params_opt are added */
| struct_or_union qual_opt_identifier type_params_opt
    { switch ($1) {
      case Struct_su:
	$$=^$(type_spec(StructType($2,$3,null),LOC(@1,@3)));
	break;
      case Union_su:
        unimp2("unions",LOC(@1,@3));
        $$=^$(Decl_spec(new_decl(Union_d,LOC(@1,@3))));
	break;
      }
    }
// Hack to allow struct/union names and typedef names to overlap
| struct_or_union QUAL_TYPEDEF_NAME type_params_opt
    { switch ($1) {
      case Struct_su:
        $$=^$(type_spec(StructType($2,$3,null),LOC(@1,@3)));
	break;
      case Union_su:
        unimp2("unions",LOC(@1,@3));
        $$=^$(Decl_spec(new_decl(Union_d,LOC(@1,@3))));
	break;
      }
    }
;

type_params_opt:
  /* empty */
    { $$=^$(null); }
| '<' type_name_list '>'
    { $$=^$(List::imp_rev($2)); }
| '<' type_name_list RIGHT_OP
    { /* RIGHT_OP is >>, we've seen one char too much, step back */
      lbuf->v->lex_curr_pos -= 1;
      $$=^$(List::imp_rev($2)); }
;

struct_or_union:
  STRUCT { $$=^$(Struct_su); }
| UNION  { $$=^$(Union_su); }
;

struct_declaration_list:
  struct_declaration_list0 { $$=^$(List::flatten(List::imp_rev($1))); }
;

/* NB: returns list in reverse order */
struct_declaration_list0:
  struct_declaration
    { $$=^$(&List($1,null)); }
| struct_declaration_list0 struct_declaration
    { $$=^$(&List($2,$1)); }
;

init_declarator_list:
  init_declarator_list0 { $$=^$(List::imp_rev($1)); }
;

/* NB: returns list in reverse order */
init_declarator_list0:
  init_declarator
    { $$=^$(&List($1,null)); }
| init_declarator_list0 ',' init_declarator
    { $$=^$(&List($3,$1)); }
;

init_declarator:
  declarator
    { $$=^$(&$($1,null)); }
| declarator '=' initializer
    { $$=^$(&$($1,(exp_opt)$3)); } // FIX: cast needed
;

struct_declaration:
  specifier_qualifier_list struct_declarator_list ';'
    {
      /* when we collapse the specifier_qualifier_list and
       * struct_declarator_list, we get a list of (1) optional id,
       * (2) type, and (3) in addition any nested struct, union,
       * or enum declarations.  For now, we warn about the nested
       * declarations.  We must check that each id is actually present
       * and then convert this to a list of struct fields: (1) id,
       * (2) tqual, (3) type. */
      tqual tq = (*$1)[0];
      let atts = (*$1)[2];
      let t = speclist2typ((*$1)[1], LOC(@1,@1));
      let info = apply_tmss(tq,t,$2,atts);
      $$=^$(List::map_c(make_struct_field,LOC(@1,@2),info));
    }
;

specifier_qualifier_list:
  type_specifier attributes_opt
    // FIX: casts needed
    { $$=^$(&$(empty_tqual(),(list_t<type_specifier_t>)(&List($1,null)),
               $2)); }
| type_specifier attributes_opt specifier_qualifier_list
    { $$=^$(&$((*$3)[0],(list_t<type_specifier_t>)(&List($1,(*$3)[1])),
               List::append($2,(*$3)[2]))); }
| type_qualifier attributes_opt
    { $$=^$(&$($1,null,$2)); }
| type_qualifier attributes_opt specifier_qualifier_list
    { $$=^$(&$(combine_tqual($1,(*$3)[0]),(*$3)[1],
               List::append($2,(*$3)[2]))); }

struct_declarator_list:
  struct_declarator_list0 { $$=^$(List::imp_rev($1)); }
;

/* NB: returns list in reverse order */
struct_declarator_list0:
  struct_declarator
    { $$=^$(&List($1,null)); }
| struct_declarator_list0 ',' struct_declarator
    { $$=^$(&List($3,$1)); }
;

struct_declarator:
  declarator
    { $$=$!1; }
| ':' constant_expression
    { /* FIX: TEMPORARY TO TEST PARSING */
      unimp2("bit fields",LOC(@1,@2));
      // Fix: cast needed
      $$=^$(&Declarator(&$(Rel_n(null),new {""}),null)); }
| declarator ':' constant_expression
    { unimp2("bit fields",LOC(@1,@2));
      $$=$!1; }
;

enum_specifier:
  ENUM '{' enumerator_list '}'
    { $$ = ^$(Decl_spec(enum_decl(Public,null,null,&Opt($3),LOC(@1,@4))));
      unimp2("anonymous enums",LOC(@1,@4));
    }
/* Cyc: added type params */
| ENUM qual_opt_identifier type_params_opt '{' enumerator_list '}'
    { let ts = List::map_c(typ2tvar,LOC(@3,@3),$3);
      $$ = ^$(Decl_spec(enum_decl(Public,&Opt($2),ts,&Opt($5),LOC(@1,@6))));
    }
| ENUM qual_opt_identifier type_params_opt
    { $$=^$(type_spec(EnumType($2,$3,null),LOC(@1,@3))); }
| XENUM qual_opt_identifier '{' enumerator_list '}'
    { $$ = ^$(Decl_spec(xenum_decl(Public,$2,$4,LOC(@1,@5)))); }
| XENUM qual_opt_identifier
    { $$=^$(type_spec(XenumType($2,null),LOC(@1,@2))); }
;

enumerator_list:
  enumerator                     { $$=^$(&List($1,null)); }
| enumerator ';'                 { $$=^$(&List($1,null)); }
| enumerator ',' enumerator_list { $$=^$(&List($1,$3)); }
| enumerator ';' enumerator_list { $$=^$(&List($1,$3)); }
;

enumerator:
  qual_opt_identifier
    { $$=^$(&Enumfield($1,null,null,null,LOC(@1,@1))); }
| qual_opt_identifier '=' constant_expression
    { $$=^$(&Enumfield($1,$3,null,null,LOC(@1,@3))); }
/* Cyc: value-carrying enumerators */
| qual_opt_identifier type_params_opt '(' parameter_list ')'
    { let typs = List::map_c(get_tqual_typ,LOC(@4,@4),List::imp_rev($4));
      let tvs  = List::map_c(typ2tvar,LOC(@2,@2),$2);
      $$=^$(&Enumfield($1,null,tvs,typs,LOC(@1,@5))); }

declarator:
  direct_declarator
    { $$=$!1; }
| pointer direct_declarator
    { $$=^$(&Declarator($2->id,List::imp_append($1,$2->tms))); }
;

direct_declarator:
  qual_opt_identifier
    { $$=^$(&Declarator($1,null)); }
| '(' declarator ')'
    { $$=$!2; }
| direct_declarator '[' ']' 
    { $$=^$(&Declarator($1->id,&List(Carray_mod,$1->tms)));
    }
| direct_declarator '[' assignment_expression ']' 
    { $$=^$(&Declarator($1->id,&List(ConstArray_mod($3),$1->tms)));
    }
| direct_declarator '(' parameter_type_list ')'
    { let &$(lis,b,eff) = $3;
      $$=^$(&Declarator($1->id,&List(Function_mod(WithTypes(lis,b,eff)),
				     $1->tms)));
    }
| direct_declarator '(' ')'
    { $$=^$(&Declarator($1->id,&List(Function_mod(WithTypes(null,false,null)),
				     $1->tms)));
    }
| direct_declarator '(' ';' effect_set ')'
    { $$=^$(&Declarator($1->id,
                        &List(Function_mod(WithTypes(null,false,
                                                     &Opt(JoinEff($4)))),
                              $1->tms)));
    }
| direct_declarator '(' identifier_list ')'
    { $$=^$(&Declarator($1->id,&List(Function_mod(NoTypes($3,LOC(@1,@4))),
				     $1->tms))); }
/* Cyc: added type parameters */
| direct_declarator '<' type_name_list '>'
    { let ts = List::map_c(typ2tvar,LOC(@2,@4),List::imp_rev($3));
      $$=^$(&Declarator($1->id,&List(TypeParams_mod(ts,LOC(@1,@4),false),
                                     $1->tms)));
    }
| direct_declarator '<' type_name_list RIGHT_OP
    { /* RIGHT_OP is >>, we've seen one char too much, step back */
      lbuf->v->lex_curr_pos -= 1;
      let ts = List::map_c(typ2tvar,LOC(@2,@4),List::imp_rev($3));
      $$=^$(&Declarator($1->id,&List(TypeParams_mod(ts,LOC(@1,@4),false),
                                     $1->tms)));
    }
| direct_declarator attributes
  { 
    $$=^$(&Declarator($1->id,&List(Attributes_mod(LOC(@2,@2),$2),$1->tms)));
  }
;

/* CYC: region annotations allowed */
pointer:
  pointer_char rgn_opt
    { $$=^$(&List(Pointer_mod($1,$2,empty_tqual()),null)); }
| pointer_char rgn_opt type_qualifier_list
    { $$=^$(&List(Pointer_mod($1,$2,$3),null)); }
| pointer_char rgn_opt pointer
    { $$=^$(&List(Pointer_mod($1,$2,empty_tqual()),$3)); }
| pointer_char rgn_opt type_qualifier_list pointer
    { $$=^$(&List(Pointer_mod($1,$2,$3),$4)); }
;

pointer_char:
  '*' { $$=^$(Nullable_ps(signed_int_exp(1,LOC(@1,@1))));  }
/* CYC: pointers that cannot be null */
| '@' { $$=^$(NonNullable_ps(signed_int_exp(1,LOC(@1,@1)))); }
/* possibly null, with array bound given by the expresion */
| '*' '{' assignment_expression '}' {$$=^$(Nullable_ps($3));}
/* not null, with array bound given by the expresion */
| '@' '{' assignment_expression '}' {$$=^$(NonNullable_ps($3));}
/* tagged pointer -- bounds maintained dynamically */
| '?' { $$=^$(TaggedArray_ps); }

rgn_opt:
    /* empty */ { $$ = ^$(HeapRgn); }
| TYPE_VAR      
  { $$ = ^$(id2type($1,new_conref(RgnKind))); }
| TYPE_VAR COLON_COLON kind
  { if ($3 != RgnKind) err("expecting region kind\n",LOC(@3,@3));
    $$ = ^$(id2type($1,new_conref(RgnKind))); 
  }
| '_' { $$ = ^$(new_evar(RgnKind)); }
;

type_qualifier_list:
  type_qualifier
    { $$ = $!1; }
| type_qualifier_list type_qualifier
    { $$ = ^$(combine_tqual($1,$2)); }
;

parameter_type_list:
  parameter_list
    { $$=^$(&$(List::imp_rev($1),false,null)); }
| parameter_list ',' ELLIPSIS
    { $$=^$(&$(List::imp_rev($1),true,null)); }
/* Cyc: add effect */
| parameter_list ';' effect_set
    { $$=^$(&$(List::imp_rev($1),false,(opt_t<typ>)&Opt(JoinEff($3)))); }
;

/* CYC:  new */
effect_set:
  atomic_effect { $$=$!1; }
| atomic_effect '+' effect_set { $$=^$(List::imp_append($1,$3)); }
;

atomic_effect:
  '{' '}'                   { $$=^$(null); }
| '{' region_set '}'        { $$=$!2; }
| TYPE_VAR                  
  { $$=^$(&List(id2type($1,new_conref(EffKind)),null)); }
| TYPE_VAR COLON_COLON kind 
  { if ($3 != EffKind) err("expecing effect kind (E)",LOC(@3,@3));
    $$=^$(&List(id2type($1,new_conref(EffKind)),null));
  }
; 

/* CYC:  new */
region_set:
  TYPE_VAR 
  { $$=^$(&List(AccessEff(id2type($1,new_conref(RgnKind))),null)); }
| TYPE_VAR ',' region_set 
  { $$=^$(&List(AccessEff(id2type($1,new_conref(RgnKind))),$3)); }
| TYPE_VAR COLON_COLON kind 
  { if ($3 != RgnKind) err("expecting region kind (R)", LOC(@3,@3));
    $$=^$(&List(AccessEff(id2type($1,new_conref(RgnKind))),null)); }
| TYPE_VAR COLON_COLON kind ',' region_set 
  { if ($3 != RgnKind) err("expecting region kind (R)", LOC(@3,@3));
    $$=^$(&List(AccessEff(id2type($1,new_conref(RgnKind))),$5)); }
;

/* NB: returns list in reverse order */
parameter_list:
  parameter_declaration
    { $$=^$(&List($1,null)); }
| parameter_list ',' parameter_declaration
    { $$=^$(&List($3,$1)); }
;

/* TODO: differs from grammar in K&R */
parameter_declaration:
  specifier_qualifier_list declarator
   {  let t   = speclist2typ((*$1)[1], LOC(@1,@1));
      let atts = (*$1)[2];
      let tq  = (*$1)[0];
      let tms = $2->tms;
      let t_info = apply_tms(tq,t,atts,tms);
      if (t_info[2] != null)
        err("parameter with bad type params",LOC(@2,@2));
      let q = $2->id;
      switch ((*q)[0]) {
      case Loc_n: break;
      case Rel_n(null): break;
      case Abs_n(null): break;
      default:
        err("parameter cannot be qualified with a module name",LOC(@1,@1));
        break;
      }
      let idopt = (opt_t<var>)&Opt((*q)[1]);
      if (t_info[3] != null) 
        warn("extra attributes on parameter, ignoring",LOC(@1,@2));
      if (t_info[2] != null)
        warn("extra type variables on parameter, ignoring",LOC(@1,@2));
      $$=^$(&$(idopt,t_info[0],t_info[1]));
    }
| specifier_qualifier_list
    { let t  = speclist2typ((*$1)[1], LOC(@1,@1));
      let atts = (*$1)[2];
      let tq = (*$1)[0];
      if (atts != null)
        warn("bad attributes on parameter, ignoring",LOC(@1,@1));
      $$=^$(&$(null,tq,t));
    }
| specifier_qualifier_list abstract_declarator
    { let t   = speclist2typ((*$1)[1], LOC(@1,@1));
      let atts = (*$1)[2];
      let tq  = (*$1)[0];
      let tms = $2->tms;
      let t_info = apply_tms(tq,t,atts,tms);
      if (t_info[2] != null)
        // Ex: int (@)<`a>
        warn("bad type parameters on formal argument, ignoring",LOC(@1,@2));
      if (t_info[3] != null)
        warn("bad attributes on parameter, ignoring",LOC(@1,@2));
      $$=^$(&$(null,t_info[0],t_info[1]));
    }
/*
| type_name
    { $$=$!1; }
*/
;

identifier_list:
  identifier_list0
    { $$=^$(List::imp_rev($1)); }
;

/* NB: returns list in reverse order */
identifier_list0:
  IDENTIFIER
    { $$=^$(&List(new {$1},null)); }
| identifier_list0 ',' IDENTIFIER
    { $$=^$(&List(new {$3},$1)); }
;

initializer:
  assignment_expression
    { $$=$!1; }
| '{' '}'
    { $$=^$(new_exp(UnresolvedMem_e(null,null),LOC(@1,@2))); }
| '{' initializer_list '}'
    { $$=^$(new_exp(UnresolvedMem_e(null,List::imp_rev($2)),LOC(@1,@3))); }
| '{' initializer_list ',' '}'
    { $$=^$(new_exp(UnresolvedMem_e(null,List::imp_rev($2)),LOC(@1,@4))); }
;

/* NB: returns list in reverse order */
initializer_list:
  initializer
    { $$=^$(&List(&$(null,$1),null)); }
| designation initializer
    { $$=^$(&List(&$($1,$2),null)); }
| initializer_list ',' initializer
    { $$=^$(&List(&$(null,$3),$1)); }
| initializer_list ',' designation initializer
    { $$=^$(&List(&$($3,$4),$1)); }
;

designation:
  designator_list '=' { $$=^$(List::imp_rev($1)); }
;

/* NB: returns list in reverse order */
designator_list:
  designator
    { $$=^$(&List($1,null)); }
| designator_list designator
    { $$=^$(&List($2,$1)); }
;

designator:
  '[' constant_expression ']' {$$ = ^$(ArrayElement($2));}
| '.' IDENTIFIER              {$$ = ^$(FieldName(new {$2}));}
;

type_name:
  specifier_qualifier_list
    { let t  = speclist2typ((*$1)[1], LOC(@1,@1));
      let atts = (*$1)[2];
      if (atts != null)
        warn("ignoring attributes in type",LOC(@1,@1));
      let tq = (*$1)[0];
      $$=^$(new{$(null,tq,t)});
    }
| specifier_qualifier_list abstract_declarator
    { let t   = speclist2typ((*$1)[1], LOC(@1,@1));
      let atts = (*$1)[2];
      let tq  = (*$1)[0];
      let tms = $2->tms;
      let t_info = apply_tms(tq,t,atts,tms);
      if (t_info[2] != null)
        // Ex: int (@)<`a>
        warn("bad type params, ignoring",LOC(@2,@2));
      if (t_info[3] != null)
        warn("bad specifiers, ignoring",LOC(@2,@2));
      $$=^$(&$(null,t_info[0],t_info[1]));
    }
;

any_type_name:
  type_name { $$ = ^$((*$1)[2]); }
| '{' '}' { $$ = ^$(JoinEff(null)); }
| '{' region_set '}' { $$ = ^$(JoinEff($2)); }
| any_type_name '+' atomic_effect { $$ = ^$(JoinEff(&List($1,$3))); }
;

/* Cyc: new */
/* NB: returns list in reverse order */
type_name_list:
  any_type_name { $$=^$(&List($1,null)); }
| type_name_list ',' any_type_name {$$=^$(&List($3,$1)); }
;

abstract_declarator:
  pointer
    { $$=^$(&Abstractdeclarator($1)); }
| direct_abstract_declarator
    { $$=$!1; }
| pointer direct_abstract_declarator
    { $$=^$(&Abstractdeclarator(List::imp_append($1,$2->tms))); }
;

direct_abstract_declarator:
  '(' abstract_declarator ')'
    { $$=$!2; }
| '[' ']'
    { $$=^$(&Abstractdeclarator(&List(Carray_mod,null))); }
| direct_abstract_declarator '[' ']'
    { $$=^$(&Abstractdeclarator(&List(Carray_mod,$1->tms))); }
| '[' assignment_expression ']'
    { $$=^$(&Abstractdeclarator(&List(ConstArray_mod($2),null))); }
| direct_abstract_declarator '[' assignment_expression ']'
    { $$=^$(&Abstractdeclarator(&List(ConstArray_mod($3),$1->tms))); 
    }
| '(' ')'
    { $$=^$(&Abstractdeclarator(&List(Function_mod(WithTypes(null,false,null)),
				      null)));
    }
| '(' ';' effect_set ')'
    { $$=^$(&Abstractdeclarator(&List(Function_mod(WithTypes(null,false,
                                                             &Opt(JoinEff($3)))
                                                   ),null)));
    }
| '(' parameter_type_list ')'
    { let &$(lis,b,eff) = $2;
      $$=^$(&Abstractdeclarator(&List(Function_mod(WithTypes(lis,b,eff)),null)));
    }
| direct_abstract_declarator '(' ')'
    { $$=^$(&Abstractdeclarator(&List(Function_mod(WithTypes(null,false,null)),
				      $1->tms)));
    }
| direct_abstract_declarator '(' ';' effect_set ')'
   { let eff = &Opt(JoinEff($4));
      $$=^$(&Abstractdeclarator(&List(Function_mod(WithTypes(null,false,eff)),
				      $1->tms)));
    }
| direct_abstract_declarator '(' parameter_type_list ')'
    { let &$(lis,b,eff) = $3;
      $$=^$(&Abstractdeclarator(&List(Function_mod(WithTypes(lis,b,eff)),
				      $1->tms)));
    }
/* Cyc: new */
| direct_abstract_declarator '<' type_name_list '>'
    { let ts = List::map_c(typ2tvar,LOC(@2,@4),List::imp_rev($3));
      $$=^$(&Abstractdeclarator(&List(TypeParams_mod(ts,LOC(@2,@4),false),
                                      $1->tms)));
    }
| direct_abstract_declarator '<' type_name_list RIGHT_OP
    { /* RIGHT_OP is >>, we've seen one char too much, step back */
      lbuf->v->lex_curr_pos -= 1;
      let ts = List::map_c(typ2tvar,LOC(@2,@4),List::imp_rev($3));
      $$=^$(&Abstractdeclarator(&List(TypeParams_mod(ts,LOC(@2,@4),false),
                                      $1->tms)));
    }
| direct_abstract_declarator attributes
    {
      $$=^$(&Abstractdeclarator(&List(Attributes_mod(LOC(@2,@2),$2),$1->tms)));
    }
;

/***************************** STATEMENTS *****************************/
statement:
  labeled_statement     { $$=$!1; }
| expression_statement  { $$=$!1; }
| compound_statement    { $$=$!1; }
| selection_statement   { $$=$!1; }
| iteration_statement   { $$=$!1; }
| jump_statement        { $$=$!1; }
/* Cyc: cut and splice */
| CUT statement         { $$=^$(new_stmt(Cut_s($2),LOC(@1,@2))); }
| SPLICE statement      { $$=^$(new_stmt(Splice_s($2),LOC(@1,@2))); }
;

/* Cyc: Unlike C, we do not treat case and default statements as
   labeled */
labeled_statement:
  IDENTIFIER ':' statement
    { $$=^$(new_stmt(Label_s(new {$1},$3),LOC(@1,@3))); }
;

expression_statement:
  ';'            { $$=^$(skip_stmt(LOC(@1,@1))); }
| expression ';' { $$=^$(exp_stmt($1,LOC(@1,@2))); }
;

compound_statement:
  '{' '}'                 { $$=^$(skip_stmt(LOC(@1,@2))); }
| '{' block_item_list '}' { $$=$!2; }
;

block_item_list:
  block_item
    { switch ($1) {
      case TopDecls_bl(ds):
        $$=^$(flatten_declarations(ds,skip_stmt(LOC(@1,@1))));
	break;
      case FnDecl_bl(fd):
        $$=^$(flatten_decl(new_decl(Fn_d(fd),LOC(@1,@1)),
			   skip_stmt(LOC(@1,@1))));
	break;
      case Stmt_bl(s):
        $$=^$(s);
	break;
      }
    }
| block_item block_item_list
    { switch ($1) {
      case TopDecls_bl(ds):
        $$=^$(flatten_declarations(ds,$2));
	break;
      case FnDecl_bl(fd):
	$$=^$(flatten_decl(new_decl(Fn_d(fd),LOC(@1,@1)),$2));
	break;
      case Stmt_bl(s):
        $$=^$(seq_stmt(s,$2,LOC(@1,@2)));
	break;
      }
    }
;

block_item:
  declaration { $$=^$(TopDecls_bl($1)); }
| statement   { $$=^$(Stmt_bl($1)); }
/* Cyc: nested function definitions.
   The initial (return) type is required,
   to avoid parser conflicts. */
| function_definition2 { $$=^$(FnDecl_bl($1)); }

/* This has the standard shift-reduce conflict which is properly resolved. */
selection_statement:
  IF '(' expression ')' statement
    { $$=^$(ifthenelse_stmt($3,$5,skip_stmt(DUMMYLOC),LOC(@1,@5))); }
| IF '(' expression ')' statement ELSE statement
    { $$=^$(ifthenelse_stmt($3,$5,$7,LOC(@1,@7))); }
/* Cyc: the body of the switch statement cannot be an arbitrary
 * statement; it must be a list of switch_clauses */
| SWITCH '(' expression ')' '{' switch_clauses '}'
    { $$=^$(switch_stmt($3,$6,LOC(@1,@7))); }
| TRY statement CATCH '{' switch_clauses '}'
    { $$=^$(trycatch_stmt($2,$5,LOC(@1,@6))); }
;

/* Cyc: unlike C, we only allow default or case statements within
 * switches.  Also unlike C, we support a more general form of pattern
 * matching within cases. */
switch_clauses:
  /* empty */
    { $$=^$(null); }
| DEFAULT ':' block_item_list
    { $$=^$(&List(&Switch_clause(new_pat(Wild_p,LOC(@1,@1)),null,
                                 null,$3,LOC(@1,@3)),
                  null));}
| CASE pattern ':' switch_clauses
    { $$=^$(&List(&Switch_clause($2,null,null,skip_stmt(LOC(@3,@3)),
                                 LOC(@1,@4)),$4)); }
| CASE pattern ':' block_item_list switch_clauses
    { $$=^$(&List(&Switch_clause($2,null,null,$4,LOC(@1,@4)),$5)); }
| CASE pattern AND_OP expression ':' switch_clauses
    { $$=^$(&List(&Switch_clause($2,null,$4,skip_stmt(LOC(@5,@5)),
                                 LOC(@1,@6)),$6)); }
| CASE pattern AND_OP expression ':' block_item_list switch_clauses
    { $$=^$(&List(&Switch_clause($2,null,$4,$6,LOC(@1,@7)),$7)); }
;

iteration_statement:
  WHILE '(' expression ')' statement
    { $$=^$(while_stmt($3,$5,LOC(@1,@5))); }
| DO statement WHILE '(' expression ')' ';'
    { $$=^$(do_stmt($2,$5,LOC(@1,@7))); }
| FOR '(' ';' ';' ')' statement
    { $$=^$(for_stmt(false_exp(DUMMYLOC),true_exp(DUMMYLOC),false_exp(DUMMYLOC),
		     $6,LOC(@1,@6))); }
| FOR '(' ';' ';' expression ')' statement
    { $$=^$(for_stmt(false_exp(DUMMYLOC),true_exp(DUMMYLOC),$5,
		     $7,LOC(@1,@7))); }
| FOR '(' ';' expression ';' ')' statement
    { $$=^$(for_stmt(false_exp(DUMMYLOC),$4,false_exp(DUMMYLOC),
		     $7,LOC(@1,@7)));}
| FOR '(' ';' expression ';' expression ')' statement
    { $$=^$(for_stmt(false_exp(DUMMYLOC),$4,$6,
		     $8,LOC(@1,@7))); }
| FOR '(' expression ';' ';' ')' statement
    { $$=^$(for_stmt($3,true_exp(DUMMYLOC),false_exp(DUMMYLOC),
		     $7,LOC(@1,@7))); }
| FOR '(' expression ';' ';' expression ')' statement
    { $$=^$(for_stmt($3,true_exp(DUMMYLOC),$6,
		     $8,LOC(@1,@8))); }
| FOR '(' expression ';' expression ';' ')' statement
    { $$=^$(for_stmt($3,$5,false_exp(DUMMYLOC),
		     $8,LOC(@1,@8))); }
| FOR '(' expression ';' expression ';' expression ')' statement
    { $$=^$(for_stmt($3,$5,$7,
		     $9,LOC(@1,@9))); }
| FOR '(' declaration ';' ')' statement
    { let decls = $3;
      let s = for_stmt(false_exp(DUMMYLOC),true_exp(DUMMYLOC),false_exp(DUMMYLOC),
		     $6,LOC(@1,@6));
      $$=^$(flatten_declarations(decls,s));
    }
| FOR '(' declaration expression ';' ')' statement
    { let decls = $3;
      let s     = for_stmt(false_exp(DUMMYLOC),$4,false_exp(DUMMYLOC),
                           $7,LOC(@1,@7));
      $$=^$(flatten_declarations(decls,s));
    }
| FOR '(' declaration ';' expression ')' statement
    { let decls = $3;
      let s     = for_stmt(false_exp(DUMMYLOC),true_exp(DUMMYLOC),$5,
                           $7,LOC(@1,@7));
      $$=^$(flatten_declarations(decls,s));
    }
| FOR '(' declaration expression ';' expression ')' statement
    { let decls = $3;
      let s     = for_stmt(false_exp(DUMMYLOC),$4,$6,
                           $8,LOC(@1,@8));
      $$=^$(flatten_declarations(decls,s));
    }
;

jump_statement:
  GOTO IDENTIFIER ';'   { $$=^$(goto_stmt(new {$2},LOC(@1,@2))); }
| CONTINUE ';'          { $$=^$(continue_stmt(LOC(@1,@1)));}
| BREAK ';'             { $$=^$(break_stmt(LOC(@1,@1)));}
| RETURN ';'            { $$=^$(return_stmt(null,LOC(@1,@1)));}
| RETURN expression ';' { $$=^$(return_stmt($2,LOC(@1,@2)));}
/* Cyc:  explicit fallthru for switches */
| FALLTHRU ';'          { $$=^$(fallthru_stmt(null,LOC(@1,@1)));}
| FALLTHRU '(' ')' ';'  { $$=^$(fallthru_stmt(null,LOC(@1,@1)));}
| FALLTHRU '(' argument_expression_list ')' ';'
                        { $$=^$(fallthru_stmt($3,LOC(@1,@1)));}
;

/***************************** PATTERNS *****************************/
/* Cyc:  patterns */
pattern:
  '_'
    { $$=^$(new_pat(Wild_p,LOC(@1,@1)));}
| '(' pattern ')'
    { $$=$!2; }
| INTEGER_CONSTANT
    { $$=^$(new_pat(Int_p((*$1)[0],(*$1)[1]),LOC(@1,@1))); }
| '-' INTEGER_CONSTANT
    { $$=^$(new_pat(Int_p(Signed,-((*$2)[1])),LOC(@1,@2))); }
| FLOATING_CONSTANT
    { $$=^$(new_pat(Float_p($1),LOC(@1,@1)));}
/* TODO: we should allow negated floating constants too */
| CHARACTER_CONSTANT
    {$$=^$(new_pat(Char_p($1),LOC(@1,@1)));}
| NULL_kw
    {$$=^$(new_pat(Null_p,LOC(@1,@1)));}
| qual_opt_identifier
    { $$=^$(new_pat(UnknownId_p($1),LOC(@1,@1))); }
| qual_opt_identifier type_params_opt '(' tuple_pattern_list ')'
    { let tvs = List::map_c(typ2tvar,LOC(@2,@2),$2);
      $$=^$(new_pat(UnknownCall_p($1,tvs,$4),LOC(@1,@5)));
    }
| '$' '(' tuple_pattern_list ')'
    {$$=^$(new_pat(Tuple_p($3),LOC(@1,@4)));}
| qual_opt_identifier type_params_opt '{' '}'
    { let tvs = List::map_c(typ2tvar,LOC(@2,@2),$2);
      $$=^$(new_pat(UnknownFields_p($1,tvs,null),LOC(@1,@4)));
    }
| qual_opt_identifier type_params_opt '{' field_pattern_list '}'
    { let tvs = List::map_c(typ2tvar,LOC(@2,@2),$2);
      $$=^$(new_pat(UnknownFields_p($1,tvs,$4),LOC(@1,@5)));
    }
| '&' pattern
    {$$=^$(new_pat(Pointer_p($2),LOC(@1,@2)));}
| '*' IDENTIFIER
    {$$=^$(new_pat(Reference_p(new_vardecl(&$(Loc_n,new {$2}),
					   VoidType,null)),
		   LOC(@1,@2)));}
;

tuple_pattern_list:
  /* empty */
    { $$=^$(null); }
| tuple_pattern_list0
    { $$=^$(List::imp_rev($1)); }
;

/* NB: returns list in reverse order */
tuple_pattern_list0:
  pattern
    {$$=^$(&List($1,null));}
| tuple_pattern_list0 ',' pattern
    {$$=^$(&List($3,$1));}
;

field_pattern:
  pattern
    {$$=^$(&$(null,$1));}
| designation pattern
    {$$=^$(&$($1,$2));}

field_pattern_list:
  field_pattern_list0
    {$$=^$(List::imp_rev($1));}
;

field_pattern_list0:
  field_pattern
    { $$=^$(&List($1,null));}
| field_pattern_list0 ',' field_pattern
    {$$=^$(&List($3,$1)); }
;
/*
struct_pattern_list:
  struct_pattern_list0
    {$$=^$(List::imp_rev($1));}
;

struct_pattern_list0:
  struct_field_pattern
    {$$=^$(&List($1,null));}
| struct_pattern_list0 ',' struct_field_pattern
    {$$=^$(&List($3,$1)); }
;

struct_field_pattern:
  IDENTIFIER
    {$$=^$(^($1,new_pat(^raw_pat.Var($1),LOC(@1,@1))));}
| IDENTIFIER '=' pattern
    {$$=^$(^($1,$3));}
;
*/

/***************************** EXPRESSIONS *****************************/
expression:
  assignment_expression
    { $$=$!1; }
| expression ',' assignment_expression
    { $$=^$(seq_exp($1,$3,LOC(@1,@3))); }
;

assignment_expression:
  conditional_expression
    { $$=$!1; }
| unary_expression assignment_operator assignment_expression
    { $$=^$(assignop_exp($1,$2,$3,LOC(@1,@3))); }
;

assignment_operator:
  '='          { $$=^$(null); }
| MUL_ASSIGN   { $$=^$(&Opt(Times)); }
| DIV_ASSIGN   { $$=^$(&Opt(Div)); }
| MOD_ASSIGN   { $$=^$(&Opt(Mod)); }
| ADD_ASSIGN   { $$=^$(&Opt(Plus)); }
| SUB_ASSIGN   { $$=^$(&Opt(Minus)); }
| LEFT_ASSIGN  { $$=^$(&Opt(Bitlshift)); }
| RIGHT_ASSIGN { $$=^$(&Opt(Bitlrshift)); }
| AND_ASSIGN   { $$=^$(&Opt(Bitand)); }
| XOR_ASSIGN   { $$=^$(&Opt(Bitxor)); }
| OR_ASSIGN    { $$=^$(&Opt(Bitor)); }
;

conditional_expression:
  logical_or_expression
    { $$=$!1; }
| logical_or_expression '?' expression ':' conditional_expression
    { $$=^$(conditional_exp($1,$3,$5,LOC(@1,@5))); }
;

constant_expression:
  conditional_expression
    { $$=$!1; }
;

logical_or_expression:
  logical_and_expression
    { $$=$!1; }
| logical_or_expression OR_OP logical_and_expression
    { $$=^$(or_exp($1,$3,LOC(@1,@3))); }
;

logical_and_expression:
  inclusive_or_expression
    { $$=$!1; }
| logical_and_expression AND_OP inclusive_or_expression
    { $$=^$(and_exp($1,$3,LOC(@1,@3))); }
;

inclusive_or_expression:
  exclusive_or_expression
    { $$=$!1; }
| inclusive_or_expression '|' exclusive_or_expression
    { $$=^$(prim2_exp(Bitor,$1,$3,LOC(@1,@3))); }
;

exclusive_or_expression:
  and_expression
    { $$=$!1; }
| exclusive_or_expression '^' and_expression
    { $$=^$(prim2_exp(Bitxor,$1,$3,LOC(@1,@3))); }
;

and_expression:
  equality_expression
    { $$=$!1; }
| and_expression '&' equality_expression
    { $$=^$(prim2_exp(Bitand,$1,$3,LOC(@1,@3))); }
;

equality_expression:
  relational_expression
    { $$=$!1; }
| equality_expression EQ_OP relational_expression
    { $$=^$(eq_exp($1,$3,LOC(@1,@3))); }
| equality_expression NE_OP relational_expression
    { $$=^$(neq_exp($1,$3,LOC(@1,@3))); }
;

relational_expression:
  shift_expression
    { $$=$!1; }
| relational_expression '<' shift_expression 
    { $$=^$(lt_exp($1,$3,LOC(@1,@3))); }
| relational_expression '>' shift_expression
    { $$=^$(gt_exp($1,$3,LOC(@1,@3))); }
| relational_expression LE_OP shift_expression
    { $$=^$(lte_exp($1,$3,LOC(@1,@3))); }
| relational_expression GE_OP shift_expression
    { $$=^$(gte_exp($1,$3,LOC(@1,@3))); }
;

shift_expression:
  additive_expression
    { $$=$!1; }
| shift_expression LEFT_OP additive_expression
    { $$=^$(prim2_exp(Bitlshift,$1,$3,LOC(@1,@3))); }
| shift_expression RIGHT_OP additive_expression
    { $$=^$(prim2_exp(Bitlrshift,$1,$3,LOC(@1,@3))); }
;

additive_expression:
  multiplicative_expression
    { $$=$!1; }
| additive_expression '+' multiplicative_expression
    { $$=^$(prim2_exp(Plus,$1,$3,LOC(@1,@3))); }
| additive_expression '-' multiplicative_expression
    { $$=^$(prim2_exp(Minus,$1,$3,LOC(@1,@3))); }
;

multiplicative_expression:
  cast_expression
    { $$=$!1; }
| multiplicative_expression '*' cast_expression
    { $$=^$(prim2_exp(Times,$1,$3,LOC(@1,@3))); }
| multiplicative_expression '/' cast_expression
    { $$=^$(prim2_exp(Div,$1,$3,LOC(@1,@3))); }
| multiplicative_expression '%' cast_expression
    { $$=^$(prim2_exp(Mod,$1,$3,LOC(@1,@3))); }
;

cast_expression:
  unary_expression
    { $$=$!1; }
| '(' type_name ')' cast_expression
    { $$=^$(cast_exp((*$2)[2],$4,LOC(@1,@4))); }
;

unary_expression:
  postfix_expression      { $$=$!1; }
| INC_OP unary_expression { $$=^$(pre_inc_exp($2,LOC(@1,@2))); }
| DEC_OP unary_expression { $$=^$(pre_dec_exp($2,LOC(@1,@2))); }
| '&' cast_expression     { $$=^$(address_exp($2,LOC(@1,@2))); }
| '*' cast_expression     { $$=^$(deref_exp  ($2,LOC(@1,@2))); }
| '+' cast_expression     { $$=$!2; }
| unary_operator cast_expression { $$=^$(prim1_exp($1,$2,LOC(@1,@2))); }
| SIZEOF '(' type_name ')'       { $$=^$(sizeoftyp_exp((*$3)[2],LOC(@1,@4))); }
| SIZEOF unary_expression        { $$=^$(sizeofexp_exp($2,LOC(@1,@2))); }
/* Cyc: throw, printf, fprintf, sprintf */
| THROW unary_expression
    { $$=^$(throw_exp($2,LOC(@1,@2))); }
| format_primop '(' argument_expression_list ')'
    { $$=^$(primop_exp($1,$3,LOC(@1,@4))); }
| MALLOC '(' SIZEOF '(' specifier_qualifier_list ')' ')'
{ $$=^$(new_exp(Malloc_e(Typ_m(speclist2typ((*$5)[1],LOC(@5,@5)))), 
			 LOC(@1,@7))); }
| MALLOC '(' SIZEOF '(' qual_opt_identifier ')' ')'
{ $$=^$(new_exp(Malloc_e(Unresolved_m($5)),LOC(@1,@7))); }
;

format_primop:
  PRINTF  { $$=^$(Printf); }
| FPRINTF { $$=^$(Fprintf); }
| XPRINTF { $$=^$(Xprintf); }
| SCANF   { $$=^$(Scanf); }
| FSCANF  { $$=^$(Fscanf); }
| SSCANF  { $$=^$(Sscanf); }
;

unary_operator:
  '~' { $$=^$(Bitnot); }
| '!' { $$=^$(Not); }
| '-' { $$=^$(Minus); }
;

postfix_expression:
  primary_expression
    { $$= $!1; }
| postfix_expression '[' expression ']'
    { $$=^$(subscript_exp($1,$3,LOC(@1,@4))); }
| postfix_expression '(' ')'
    { $$=^$(unknowncall_exp($1,null,LOC(@1,@3))); }
| postfix_expression '(' argument_expression_list ')'
    { $$=^$(unknowncall_exp($1,$3,LOC(@1,@4))); }
| postfix_expression '.' IDENTIFIER
    { $$=^$(structmember_exp($1,new {$3},LOC(@1,@3))); }
// Hack to allow typedef names and field names to overlap
| postfix_expression '.' QUAL_TYPEDEF_NAME
    { qvar q = $3;
      switch ((*q)[0]) {
      case Loc_n: break;
      case Rel_n(null): break;
      case Abs_n(null): break;
      default:
        err("struct field name is qualified",LOC(@3,@3));
        break;
      }
      $$=^$(structmember_exp($1,(*q)[1],LOC(@1,@3)));
    }
| postfix_expression PTR_OP IDENTIFIER
    { $$=^$(structarrow_exp($1,new {$3},LOC(@1,@3))); }
// Hack to allow typedef names and field names to overlap
| postfix_expression PTR_OP QUAL_TYPEDEF_NAME
    { qvar q = $3;
      switch ((*q)[0]) {
      case Loc_n: break;
      case Rel_n(null): break;
      case Abs_n(null): break;
      default:
        err("struct field is qualified with module name",LOC(@3,@3));
        break;
      }
      $$=^$(structarrow_exp($1,(*q)[1],LOC(@1,@3)));
    }
| postfix_expression INC_OP
    { $$=^$(post_inc_exp($1,LOC(@1,@2))); }
| postfix_expression DEC_OP
    { $$=^$(post_dec_exp($1,LOC(@1,@2))); }
| '(' type_name ')' '{' initializer_list '}'
    { $$=^$(new_exp(CompoundLit_e($2,List::imp_rev($5)),LOC(@1,@6))); }
| '(' type_name ')' '{' initializer_list ',' '}'
    { $$=^$(new_exp(CompoundLit_e($2,List::imp_rev($5)),LOC(@1,@7))); }
/* Cyc: expressions to build arrays */
| NEW '{' '}'
  /* empty arrays */
    { $$=^$(new_exp(Array_e(true,null),LOC(@1,@3))); }
  /* constant-sized arrays */
| NEW '{' initializer_list '}'
    { $$=^$(new_exp(Array_e(true,List::imp_rev($3)),LOC(@1,@3))); }
| NEW '{' initializer_list ',' '}'
    { $$=^$(new_exp(Array_e(true,List::imp_rev($3)),LOC(@1,@4))); }
  /* array comprehension */
| NEW '{' FOR IDENTIFIER '<' expression ':' expression '}'
    { $$=^$(new_exp(Comprehension_e(new_vardecl(&$(Loc_n,new {$4}),
                                                uint_t,
						uint_exp(0,LOC(@4,@4))),
				    $6, $8),LOC(@1,@9))); }
| NEW STRING
    { $$=^$(string_exp(true,$2,LOC(@1,@2))); }
/* Cyc: added fill and codegen */
| FILL '(' expression ')'
    { $$=^$(new_exp(Fill_e($3),LOC(@1,@4))); }
| CODEGEN '(' function_definition ')'
    { $$=^$(new_exp(Codegen_e($3),LOC(@1,@4))); }
;

primary_expression:
  qual_opt_identifier
    /* This could be an ordinary identifier, a struct tag, or an enum or
       xenum constructor */
    { $$=^$(new_exp(UnknownId_e($1),LOC(@1,@1))); }
| constant
    { $$= $!1; }
| STRING
    { $$=^$(string_exp(false,$1,LOC(@1,@1))); }
| '(' expression ')'
    { $$= $!2; }
/* Cyc: stop instantiation */
| qual_opt_identifier LEFT_RIGHT
    { $$=^$(noinstantiate_exp(new_exp(UnknownId_e($1),LOC(@1,@1)),LOC(@1,@2)));}
| qual_opt_identifier '@' '<' type_name_list '>'
    { $$=^$(instantiate_exp(new_exp(UnknownId_e($1),LOC(@1,@1)),
			    List::imp_rev($4),LOC(@1,@5))); }
/* Cyc: tuple expressions */
| '$' '(' argument_expression_list ')'
    { $$=^$(tuple_exp($3,LOC(@1,@4))); }
/* Cyc: structure expressions */
| qual_opt_identifier '{' initializer_list '}'
    { $$=^$(new_exp(Struct_e($1,null,List::imp_rev($3),null),LOC(@1,@4))); }
/* Cyc: compound statement expressions, as in gcc */
| '(' '{' block_item_list '}' ')'
    { $$=^$(stmt_exp($3,LOC(@1,@5))); }
;

argument_expression_list:
  argument_expression_list0 { $$=^$(List::imp_rev($1)); }
;

/* NB: returns list in reverse order */
argument_expression_list0:
  assignment_expression
    { $$=^$(&List($1,null)); }
| argument_expression_list0 ',' assignment_expression
    { $$=^$(&List($3,$1)); }
;

/* NB: We've had to move enumeration constants into primary_expression
   because the lexer can't tell them from ordinary identifiers */
constant:
  INTEGER_CONSTANT   { $$=^$(int_exp((*$1)[0],(*$1)[1],LOC(@1,@1))); }
| CHARACTER_CONSTANT { $$=^$(char_exp($1,        LOC(@1,@1))); }
| FLOATING_CONSTANT  { $$=^$(float_exp($1,       LOC(@1,@1))); }
/* Cyc: null */
| NULL_kw            { $$=^$(null_exp(LOC(@1,@1)));}
;

qual_opt_identifier:
  IDENTIFIER      { $$=^$(&$(Rel_n(null),new {$1})); }
| QUAL_IDENTIFIER { $$=$!1; }
;

%%

void yyprint(int i, xenum YYSTYPE v) {
  switch (v) {
  case Okay_tok:          fprintf(stderr,"ok");         break;
  case Int_tok(&$(_,i2)): fprintf(stderr,"%d",i2);      break;
  case Char_tok(c):       fprintf(stderr,"%c",c);       break;
  case Short_tok(s):      fprintf(stderr,"%ds",(int)s); break;
  case String_tok(s):          fprintf(stderr,"\"%s\"",s); break;
  case Stringopt_tok(null):    fprintf(stderr,"null");     break;
  case Stringopt_tok(&Opt(s)): fprintf(stderr,"\"%s\"",*s); break;
  case QualId_tok(&$(p,v2)):
    let prefix = null;
    switch (p) {
    case Rel_n(x): prefix = x; break;
    case Abs_n(x): prefix = x; break;
    case Loc_n: break;
    }
    for (; prefix != null; prefix = prefix->tl)
      fprintf(stderr,"%s::",*(prefix->hd));
    fprintf(stderr,"%s::",*v2);
    break;
  default: fprintf(stderr,"?"); break;
  }
}

namespace Parse{
list_t<decl> parse_file(FILE @f) {
  parse_result = null;
  lbuf = &Opt(from_file(f));
  yyparse();
  return parse_result;
}
}
