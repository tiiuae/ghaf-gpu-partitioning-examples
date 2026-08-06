// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

typedef int CUresult;
typedef int CUdevice;
typedef struct CUctx_st *CUcontext;
typedef struct CUmod_st *CUmodule;
typedef struct CUfunc_st *CUfunction;
typedef unsigned long long CUdeviceptr;

enum { ATTR_CC_MAJOR = 75, ATTR_CC_MINOR = 76 };

extern CUresult cuInit(unsigned int);
extern CUresult cuDeviceGet(CUdevice *, int);
extern CUresult cuDeviceGetAttribute(int *, int, CUdevice);
extern CUresult cuCtxCreate_v2(CUcontext *, unsigned int, CUdevice);
extern CUresult cuModuleLoadData(CUmodule *, const void *);
extern CUresult cuModuleGetFunction(CUfunction *, CUmodule, const char *);
extern CUresult cuMemAlloc_v2(CUdeviceptr *, size_t);
extern CUresult cuLaunchKernel(CUfunction, unsigned int, unsigned int,
                               unsigned int, unsigned int, unsigned int,
                               unsigned int, unsigned int, void *, void **,
                               void **);
extern CUresult cuCtxSynchronize(void);

__asm__(".pushsection .rodata\n"
        ".global vadd_ptx\n"
        "vadd_ptx:\n"
        ".incbin \"vadd.ptx\"\n"
        ".byte 0\n"
        ".popsection\n");
extern const char vadd_ptx[];

#define CK(expression)                                                         \
  do {                                                                         \
    CUresult result = (expression);                                            \
    if (result != 0) {                                                         \
      fprintf(stderr, "%s failed: CUresult=%d\n", #expression, result);        \
      return 1;                                                                \
    }                                                                          \
  } while (0)

int main(int argc, char **argv) {
  int seconds = 20;
  size_t element_count = (size_t)1 << 20;
  CUdevice device;
  CUcontext context;
  CUmodule module;
  CUfunction function;
  CUdeviceptr output;
  int major = 0;
  int minor = 0;
  int count = (int)element_count;
  void *arguments[] = {&output, &count};
  unsigned int grid = (unsigned int)((element_count + 255) / 256);
  unsigned long iterations = 0;
  time_t started;

  if (argc > 1) {
    char *end = NULL;
    long parsed = strtol(argv[1], &end, 10);
    if (argv[1][0] == '\0' || end == NULL || *end != '\0' || parsed < 1 ||
        parsed > 86400) {
      fprintf(stderr, "invalid duration '%s' (expected 1..86400 seconds)\n",
              argv[1]);
      return 2;
    }
    seconds = (int)parsed;
  }

  CK(cuInit(0));
  CK(cuDeviceGet(&device, 0));
  CK(cuDeviceGetAttribute(&major, ATTR_CC_MAJOR, device));
  CK(cuDeviceGetAttribute(&minor, ATTR_CC_MINOR, device));
  printf("GPU compute capability: sm_%d%d\n", major, minor);
  CK(cuCtxCreate_v2(&context, 0, device));
  CK(cuModuleLoadData(&module, vadd_ptx));
  CK(cuModuleGetFunction(&function, module, "burn"));
  CK(cuMemAlloc_v2(&output, element_count * sizeof(float)));

  printf("running direct GPU load for %d s\n", seconds);
  fflush(stdout);
  started = time(NULL);
  while (time(NULL) - started < seconds) {
    CK(cuLaunchKernel(function, grid, 1, 1, 256, 1, 1, 0, NULL, arguments,
                      NULL));
    CK(cuCtxSynchronize());
    iterations++;
  }
  if (iterations == 0) {
    fprintf(stderr, "GPU_LOAD_FAIL: no kernel launches completed\n");
    return 1;
  }
  printf("GPU_LOAD_OK iterations=%lu\n", iterations);
  return 0;
}
