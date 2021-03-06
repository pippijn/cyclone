/* Model module definitions used by both the encoder and the decoder. */
#include <core.h>

#define NO_PRELOAD_LIMIT -1 /* means no limit on size of input file */

/* Routines required by encoder or decoder :

   void init_arguments(argc,argv)
       initialize any parameters from the command line arguments
   void init_symbols()
       initialize the model
   int findContext()
       choose the context & return pointer to it
   int total_symbols(context)
       return the cumulative frequencies of all symbols in the context
   int eof_symbol()
       return the end of file symbol
   void encode_symbol( context, symbol )
       encode the symbol
   int decode_symbol( context, target )
       return the decoded symbol

*/
void init_arguments(int argc, string_t? argv, int argp);
void init_symbols();
int find_context();
int eof_symbol();
void encode_symbol(int symbol, int load);
int decode_symbol();
int preloadInput();
int loadInput(FILE@ fp, int p, int max);
void startInput();
int getInput();
int lengthInput();
