// SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0
#define _POSIX_C_SOURCE 200809L
#include "plugin.h"

#include <cublas_v2.h>

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct gemm_options {
  unsigned int size;
  unsigned int seconds;
};

static uint64_t monotonic_ns(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
    return 0;
  return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
}

static bool parse_unsigned(const char *text, unsigned long minimum,
                           unsigned long maximum, unsigned int *result) {
  char *end = NULL;
  unsigned long value;

  errno = 0;
  value = strtoul(text, &end, 10);
  if (errno != 0 || text[0] == '\0' || end == NULL || *end != '\0' ||
      value < minimum || value > maximum)
    return false;
  *result = (unsigned int)value;
  return true;
}

static bool parse_options(int argc, const char *const *argv,
                          struct gemm_options *options) {
  options->size = 1024;
  options->seconds = 30;

  for (int index = 0; index < argc; index += 2) {
    if (index + 1 >= argc)
      return false;
    if (strcmp(argv[index], "--size") == 0) {
      if (!parse_unsigned(argv[index + 1], 16, 4096, &options->size))
        return false;
    } else if (strcmp(argv[index], "--seconds") == 0) {
      if (!parse_unsigned(argv[index + 1], 1, 3600, &options->seconds))
        return false;
    } else {
      return false;
    }
  }
  return true;
}

static int gemm_run(CUstream stream, unsigned int sm_count, int argc,
                    const char *const *argv,
                    const volatile sig_atomic_t *cancelled, char *report,
                    size_t report_size) {
  struct gemm_options options;
  cublasHandle_t handle = NULL;
  CUdeviceptr left = 0;
  CUdeviceptr right = 0;
  CUdeviceptr output = 0;
  CUresult cuda_result;
  cublasStatus_t cublas_result;
  size_t elements;
  size_t bytes;
  unsigned long iterations = 0;
  uint64_t started;
  uint64_t elapsed_ns;
  float samples[3] = {0};
  const float alpha = 1.0f;
  const float beta = 0.0f;
  int result = GPM_PLUGIN_CUDA_ERROR;

  if (!parse_options(argc, argv, &options)) {
    snprintf(report, report_size,
             "invalid arguments; usage: gemm [--size 16..4096] "
             "[--seconds 1..3600]");
    return GPM_PLUGIN_INVALID_ARGUMENT;
  }
  elements = (size_t)options.size * (size_t)options.size;
  bytes = elements * sizeof(float);

#define CUDA_TRY(expression)                                                   \
  do {                                                                         \
    cuda_result = (expression);                                                \
    if (cuda_result != CUDA_SUCCESS) {                                         \
      snprintf(report, report_size, "CUDA call %s failed: %d", #expression,    \
               (int)cuda_result);                                              \
      goto cleanup;                                                            \
    }                                                                          \
  } while (0)

#define CUBLAS_TRY(expression)                                                 \
  do {                                                                         \
    cublas_result = (expression);                                              \
    if (cublas_result != CUBLAS_STATUS_SUCCESS) {                              \
      snprintf(report, report_size, "cuBLAS call %s failed: %d", #expression,  \
               (int)cublas_result);                                            \
      goto cleanup;                                                            \
    }                                                                          \
  } while (0)

  CUDA_TRY(cuMemAlloc(&left, bytes));
  CUDA_TRY(cuMemAlloc(&right, bytes));
  CUDA_TRY(cuMemAlloc(&output, bytes));
  CUDA_TRY(cuMemsetD32(left, 0x3f800000U, elements));
  CUDA_TRY(cuMemsetD32(right, 0x3f800000U, elements));
  CUDA_TRY(cuMemsetD32(output, 0, elements));
  CUBLAS_TRY(cublasCreate(&handle));
  CUBLAS_TRY(cublasSetStream(handle, (cudaStream_t)stream));

  started = monotonic_ns();
  do {
    if (*cancelled != 0) {
      snprintf(report, report_size,
               "plugin=gemm status=cancelled size=%u iterations=%lu",
               options.size, iterations);
      result = GPM_PLUGIN_CANCELLED;
      goto cleanup;
    }
    CUBLAS_TRY(cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, (int)options.size,
                           (int)options.size, (int)options.size, &alpha,
                           (const float *)left, (int)options.size,
                           (const float *)right, (int)options.size, &beta,
                           (float *)output, (int)options.size));
    CUDA_TRY(cuStreamSynchronize(stream));
    iterations++;
  } while (monotonic_ns() - started <
           (uint64_t)options.seconds * 1000000000ULL);
  elapsed_ns = monotonic_ns() - started;

  CUDA_TRY(cuMemcpyDtoH(&samples[0], output, sizeof(samples[0])));
  CUDA_TRY(cuMemcpyDtoH(&samples[1], output + (elements / 2) * sizeof(float),
                        sizeof(samples[1])));
  CUDA_TRY(cuMemcpyDtoH(&samples[2], output + (elements - 1) * sizeof(float),
                        sizeof(samples[2])));
  if (samples[0] != (float)options.size || samples[0] != samples[1] ||
      samples[1] != samples[2]) {
    snprintf(report, report_size,
             "plugin=gemm validation=failed size=%u iterations=%lu sample=%g",
             options.size, iterations, samples[0]);
    result = GPM_PLUGIN_INTERNAL_ERROR;
    goto cleanup;
  }

  snprintf(report, report_size,
           "plugin=gemm status=ok sm_count=%u size=%u seconds=%u "
           "iterations=%lu gflops=%.3f sample=%g",
           sm_count, options.size, options.seconds, iterations,
           (2.0 * (double)options.size * (double)options.size *
            (double)options.size * (double)iterations) /
               (double)elapsed_ns,
           samples[0]);
  result = GPM_PLUGIN_OK;

cleanup:
  if (handle != NULL)
    (void)cublasDestroy(handle);
  if (output != 0)
    (void)cuMemFree(output);
  if (right != 0)
    (void)cuMemFree(right);
  if (left != 0)
    (void)cuMemFree(left);
  return result;
#undef CUBLAS_TRY
#undef CUDA_TRY
}

static const struct gpm_plugin_v1 plugin = {
    .abi_version = GPM_PLUGIN_ABI_VERSION,
    .name = "gemm",
    .summary = "Validated cuBLAS SGEMM workload on the assigned stream",
    .run = gemm_run,
};

const struct gpm_plugin_v1 *gpm_plugin_get_v1(void) { return &plugin; }
