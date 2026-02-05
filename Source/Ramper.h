// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#ifndef _RAMPER_H_
#define _RAMPER_H_

#include <sys/types.h>

typedef struct Ramper Ramper;

extern Ramper *RamperCreate(void);
extern void RamperFree(Ramper *self);

extern void RamperProcess(Ramper *self, float *left, float *right, size_t frameCount);

extern void RamperReset(Ramper *self);
extern void RamperUpdate(Ramper *self, int shouldPlay, size_t frameDuration);

#endif
