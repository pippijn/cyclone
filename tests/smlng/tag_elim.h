#ifndef TAG_ELIM_H
#define TAG_ELIM_H

#include "smlng.h"
#include "buffer.h"

namespace TagElim {
extern struct SynthS {
  bool bold: 1;
  //  bool emph: 1;
  bool ital: 1;
  bool strong: 1;
  bool plain: 1;
  bool tt: 1;
  bool u1: 1; // invariant: true if u2 is true
  bool u2: 1; // invariant: true if u3 is true
  bool u3: 1;
  bool color: 1;
  bool sz: 1;
  int sizes: 10; // 0 at bit n means n DOES get used as a size
  int colors: 8; // 0 at bit n means n DOES get used as a color
};
extern union Synth {
  struct SynthS s;
  unsigned int i;
};
typedef union Synth synth_t; // not a pointer
extern $(doc_t, synth_t) up_opt(Buffer::buf_t, doc_t);
}

#endif
