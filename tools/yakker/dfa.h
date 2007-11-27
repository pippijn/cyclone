#ifndef DFA_H_
#define DFA_H_
#include "fa.h"

namespace DFA {
	struct dfa_kit {
	  dfa_t dfa;
	  // start state is implicitly state 1.
	  // Set of final states for the *whole* dfa. This is *not*
	  // the set of all final states, including those of symbols, in the dfa.
	  Set::set_t<st_t> final_states;

	  unsigned int symb_action_counter;
	  struct Hashtable::Table<str_t,act_t> @symb_action_table;
	  struct Hashtable::Table<act_t,str_t> @action_symb_table;

	  xarray_t<st_t> symbol_start_states;
	  xarray_t<Set::set_t<st_t>> symbol_final_states;
	};
  
  typedef struct dfa_kit@ dfa_kit_t;
  
  //////////
  // Accessor functions (basic)
  /////////

  // Get the start state of the dfa itself.
  extern st_t get_dfa_start(dfa_kit k);
  // Get the set of final states for the dfa itself.
  extern Set::set_t<st_t> get_dfa_finals(dfa_kit k);
  // Get the set of final states for all symbols in the dfa.
  extern Set::set_t<st_t> get_all_symbol_finals(dfa_kit k);
  
  // Get the start state for the specified symbol-action.
  extern st_t get_symbol_start(dfa_kit k, act_t symb_act);
  // Get the final states for the specified symbol-action.
  extern Set::set_t<st_t> get_symbol_finals(dfa_kit k, act_t symb_act);

  extern st_t new_state(dfa_kit k);
  
  // Create a new symbol-action for the symbol argument.
  extern act_t new_symact(dfa_kit k, const char ?symb);
  // Get the action for the specified symbol.
  extern act_t lookup_symact(dfa_kit k, const char ?symb);
  // Map a symbol-action to a symbol.
  extern const char ?lookup_symbol(dfa_kit k, act_t act);

  ////////
  // Convenience functions for extending the dfa in various ways.
  ////////
  extern st_t mk_call(dfa_kit_t dk, const char ?symb, st_t final);
  extern st_t mk_lit(dfa_kit_t dk, const char ?lit, st_t final);
  extern st_t mk_char(dfa_kit_t dk, char c, st_t final);
}

#endif /*DFA_H_*/
