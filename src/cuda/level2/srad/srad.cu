// includes, system
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "srad.h"

#include "OptionParser.h"
#include "ResultDatabase.h"
#include "cudacommon.h"

// includes, project
#include <cuda.h>

// includes, kernels
#include "srad_kernel.cu"

#define SEED 7

float kernelTime = 0.0f;
float transferTime = 0.0f;
cudaEvent_t start, stop;
float elapsed;
float *check;

void random_matrix(float *I, int rows, int cols);
void runTest(int argc, char **argv);
float srad(ResultDatabase &resultDB, OptionParser &op, float* matrix, int imageSize, int speckleSize, int iters);
float srad_gridsync(ResultDatabase &resultDB, OptionParser &op, float* matrix, int imageSize, int speckleSize, int iters);

void addBenchmarkSpecOptions(OptionParser &op) {
  op.addOption("imageSize", OPT_INT, "0", "image height and width");
  op.addOption("speckleSize", OPT_INT, "0", "speckle height and width");
  op.addOption("iterations", OPT_INT, "0", "iterations of algorithm");
  op.addOption("resultfile", OPT_STRING, "", "file to write results to");
}

void RunBenchmark(ResultDatabase &resultDB, OptionParser &op) {
  srand(SEED);
  printf("WG size of kernel = %d X %d\n", BLOCK_SIZE, BLOCK_SIZE);

  // set parameters
  int imageSize = op.getOptionInt("imageSize");
  int speckleSize = op.getOptionInt("speckleSize");
  int iters = op.getOptionInt("iterations");
  if (imageSize == 0 || speckleSize == 0 || iters == 0) {
    int imageSizes[4] = {128, 512, 4096, 2 << 13};
    int iterSizes[4] = {5, 10, 15, 20};
    imageSize = imageSizes[op.getOptionInt("size") - 1];
    speckleSize = imageSize / 2;
    iters = iterSizes[op.getOptionInt("size") - 1];
  }

  // create timing events
  cudaEventCreate(&start);
  cudaEventCreate(&stop);

  printf("Image Size: %d x %d\n", imageSize, imageSize);
  printf("Speckle size: %d x %d\n", speckleSize, speckleSize);
  printf("Num Iterations: %d\n", iters);

  // run workload
  int passes = op.getOptionInt("passes");
  for (int i = 0; i < passes; i++) {
    float *matrix = (float*)malloc(imageSize * imageSize * sizeof(float));
    random_matrix(matrix, imageSize, imageSize);
    printf("Pass %d:\n", i);
    float time = srad(resultDB, op, matrix, imageSize, speckleSize, iters);
    printf("Running SRAD...Done.\n");
#ifdef GRID_SYNC
    // if using cooperative groups, add result to compare the 2 times
    char atts[1024];
    sprintf(atts, "img:%d,speckle:%d,iter:%d", imageSize, speckleSize, iters);
    float time_gridsync = srad_gridsync(resultDB, op, matrix, imageSize, speckleSize, iters);
    if(time_gridsync == FLT_MAX) {
        printf("Running SRAD with cooperative groups...Failed.\n");
    } else {
        printf("Running SRAD with cooperative groups...Done.\n");
        resultDB.AddResult("srad_time/srad_cg_time", atts, "N", time/time_gridsync);
    }
#endif
      free(matrix);
  }
}

float srad(ResultDatabase &resultDB, OptionParser &op, float* matrix, int imageSize,
          int speckleSize, int iters) {
    kernelTime = 0.0f;
    transferTime = 0.0f;
    int rows, cols, size_I, size_R, niter, iter;
    float *I, *J, lambda, q0sqr, sum, sum2, tmp, meanROI, varROI;

#ifdef GPU

  float *J_cuda;
  float *C_cuda;
  float *E_C, *W_C, *N_C, *S_C;

#endif

  unsigned int r1, r2, c1, c2;
  float *c;

  rows = imageSize;  // number of rows in the domain
  cols = imageSize;  // number of cols in the domain
  if ((rows % 16 != 0) || (cols % 16 != 0)) {
    fprintf(stderr, "rows and cols must be multiples of 16\n");
    exit(1);
  }
  r1 = 0;            // y1 position of the speckle
  r2 = speckleSize;  // y2 position of the speckle
  c1 = 0;            // x1 position of the speckle
  c2 = speckleSize;  // x2 position of the speckle
  lambda = 0.5;      // Lambda value
  niter = iters;     // number of iterations

  size_I = cols * rows;
  size_R = (r2 - r1 + 1) * (c2 - c1 + 1);

  I = (float *)malloc(size_I * sizeof(float));
  J = (float *)malloc(size_I * sizeof(float));
  c = (float *)malloc(sizeof(float) * size_I);

#ifdef GPU

  // Allocate device memory
  CUDA_SAFE_CALL(cudaMalloc((void **)&J_cuda, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&C_cuda, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&E_C, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&W_C, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&S_C, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&N_C, sizeof(float) * size_I));

#endif

  // copy random matrix
  memcpy(I, matrix, rows*cols*sizeof(float));

  for (int k = 0; k < size_I; k++) {
    J[k] = (float)exp(I[k]);
  }
  for (iter = 0; iter < niter; iter++) {
    sum = 0;
    sum2 = 0;
    for (int i = r1; i <= r2; i++) {
      for (int j = c1; j <= c2; j++) {
        tmp = J[i * cols + j];
        sum += tmp;
        sum2 += tmp * tmp;
      }
    }
    meanROI = sum / size_R;
    varROI = (sum2 / size_R) - meanROI * meanROI;
    q0sqr = varROI / (meanROI * meanROI);

#ifdef GPU
    // Currently the input size must be divided by 16 - the block size
    int block_x = cols / BLOCK_SIZE;
    int block_y = rows / BLOCK_SIZE;

    dim3 dimBlock(BLOCK_SIZE, BLOCK_SIZE);
    dim3 dimGrid(block_x, block_y);

    // Copy data from main memory to device memory
    cudaEventRecord(start, 0);
    CUDA_SAFE_CALL(
        cudaMemcpy(J_cuda, J, sizeof(float) * size_I, cudaMemcpyHostToDevice));
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&elapsed, start, stop);
    transferTime += elapsed * 1.e-3;

    // Run kernels
    cudaEventRecord(start, 0);
    srad_cuda_1<<<dimGrid, dimBlock>>>(E_C, W_C, N_C, S_C, J_cuda, C_cuda, cols,
                                       rows, q0sqr);
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&elapsed, start, stop);
    kernelTime += elapsed * 1.e-3;
    CHECK_CUDA_ERROR();

    cudaEventRecord(start, 0);
    srad_cuda_2<<<dimGrid, dimBlock>>>(E_C, W_C, N_C, S_C, J_cuda, C_cuda, cols,
                                       rows, lambda, q0sqr);
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&elapsed, start, stop);
    kernelTime += elapsed * 1.e-3;
    CHECK_CUDA_ERROR();

    // Copy data from device memory to main memory
    cudaEventRecord(start, 0);
    CUDA_SAFE_CALL(
        cudaMemcpy(J, J_cuda, sizeof(float) * size_I, cudaMemcpyDeviceToHost));
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&elapsed, start, stop);
    transferTime += elapsed * 1.e-3;
#endif
  }

    char atts[1024];
    sprintf(atts, "img:%d,speckle:%d,iter:%d", imageSize, speckleSize, iters);
    resultDB.AddResult("srad_kernel_time", atts, "sec", kernelTime);
    resultDB.AddResult("srad_transfer_time", atts, "sec", transferTime);
    resultDB.AddResult("srad_total_time", atts, "sec", kernelTime + transferTime);
    resultDB.AddResult("srad_parity", atts, "N", transferTime / kernelTime);

  string resultfile = op.getOptionString("resultfile");
  if(!resultfile.empty()) {
      // Printing output
      printf("Writing output to %s\n", resultfile.c_str());
      FILE *fp = NULL;
      fp = fopen(resultfile.c_str(), "w");
      if(!fp) {
          printf("Error: Unable to write to file %s\n", resultfile.c_str());
      } else {
          for (int i = 0; i < rows; i++) {
              for (int j = 0; j < cols; j++) {
                  fprintf(fp, "%.5f ", J[i * cols + j]);
              }
              fprintf(fp, "\n");
          }
          fclose(fp);
      }
  }
  // write results to validate with srad_gridsync
  check = (float*) malloc(sizeof(float) * size_I);
  for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
          check[i*cols+j] = J[i*cols+j];
      }
  }

  free(I);
  free(J);
  free(c);
#ifdef GPU
  CUDA_SAFE_CALL(cudaFree(C_cuda));
  CUDA_SAFE_CALL(cudaFree(J_cuda));
  CUDA_SAFE_CALL(cudaFree(E_C));
  CUDA_SAFE_CALL(cudaFree(W_C));
  CUDA_SAFE_CALL(cudaFree(N_C));
  CUDA_SAFE_CALL(cudaFree(S_C));
#endif
    return kernelTime + transferTime;
}

#ifdef GRID_SYNC
float srad_gridsync(ResultDatabase &resultDB, OptionParser &op, float* matrix, int imageSize,
          int speckleSize, int iters) {
    kernelTime = 0.0f;
    transferTime = 0.0f;
    int rows, cols, size_I, size_R, niter, iter;
    float *I, *J, lambda, q0sqr, sum, sum2, tmp, meanROI, varROI;


#ifdef GPU

  float *J_cuda;
  float *C_cuda;
  float *E_C, *W_C, *N_C, *S_C;

#endif

  unsigned int r1, r2, c1, c2;
  float *c;

  rows = imageSize;  // number of rows in the domain
  cols = imageSize;  // number of cols in the domain
  if ((rows % 16 != 0) || (cols % 16 != 0)) {
    fprintf(stderr, "rows and cols must be multiples of 16\n");
    exit(1);
  }
  r1 = 0;            // y1 position of the speckle
  r2 = speckleSize;  // y2 position of the speckle
  c1 = 0;            // x1 position of the speckle
  c2 = speckleSize;  // x2 position of the speckle
  lambda = 0.5;      // Lambda value
  niter = iters;     // number of iterations

  size_I = cols * rows;
  size_R = (r2 - r1 + 1) * (c2 - c1 + 1);

  I = (float *)malloc(size_I * sizeof(float));
  J = (float *)malloc(size_I * sizeof(float));
  c = (float *)malloc(sizeof(float) * size_I);

#ifdef GPU

  // Allocate device memory
  CUDA_SAFE_CALL(cudaMalloc((void **)&J_cuda, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&C_cuda, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&E_C, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&W_C, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&S_C, sizeof(float) * size_I));
  CUDA_SAFE_CALL(cudaMalloc((void **)&N_C, sizeof(float) * size_I));

#endif

  // Generate a random matrix
  memcpy(I, matrix, rows*cols*sizeof(float));

  for (int k = 0; k < size_I; k++) {
    J[k] = (float)exp(I[k]);
  }
  for (iter = 0; iter < niter; iter++) {
    sum = 0;
    sum2 = 0;
    for (int i = r1; i <= r2; i++) {
      for (int j = c1; j <= c2; j++) {
        tmp = J[i * cols + j];
        sum += tmp;
        sum2 += tmp * tmp;
      }
    }
    meanROI = sum / size_R;
    varROI = (sum2 / size_R) - meanROI * meanROI;
    q0sqr = varROI / (meanROI * meanROI);

#ifdef GPU
    // Currently the input size must be divided by 16 - the block size
    int block_x = cols / BLOCK_SIZE;
    int block_y = rows / BLOCK_SIZE;

    dim3 dimBlock(BLOCK_SIZE, BLOCK_SIZE);
    dim3 dimGrid(block_x, block_y);

    // Copy data from main memory to device memory
    cudaEventRecord(start, 0);
    CUDA_SAFE_CALL(
        cudaMemcpy(J_cuda, J, sizeof(float) * size_I, cudaMemcpyHostToDevice));
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&elapsed, start, stop);
    transferTime += elapsed * 1.e-3;

    // Run kernels
    cudaEventRecord(start, 0);
    srad_cuda_3<<<dimGrid, dimBlock>>>(E_C, W_C, N_C, S_C, J_cuda, C_cuda, cols,
                                       rows, lambda, q0sqr);
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&elapsed, start, stop);
    kernelTime += elapsed * 1.e-3;
    CHECK_CUDA_ERROR();

    // Copy data from device memory to main memory
    cudaEventRecord(start, 0);
    CUDA_SAFE_CALL(
        cudaMemcpy(J, J_cuda, sizeof(float) * size_I, cudaMemcpyDeviceToHost));
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&elapsed, start, stop);
    transferTime += elapsed * 1.e-3;
#endif
  }

    char atts[1024];
    sprintf(atts, "img:%d,speckle:%d,iter:%d", imageSize, speckleSize, iters);
    resultDB.AddResult("srad_gridsync_kernel_time", atts, "sec", kernelTime);
    resultDB.AddResult("srad_gridsync_transer_time", atts, "sec", transferTime);
    resultDB.AddResult("srad_gridsync_total_time", atts, "sec", kernelTime + transferTime);
    resultDB.AddResult("srad_gridsync_parity", atts, "N", transferTime / kernelTime);

  // validate result with result obtained by gridsync
  for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
          if(check[i*cols+j] - J[i*cols+j] < 0.001) {
              // known bug: with and without gridsync have 10e-5 difference in row 16
              printf("Error: Validation failed at row %d, col %d\n", i, j);
              printf("%0.6f vs %0.6f\n", check[i*cols+j], J[i*cols+j]);
              return FLT_MAX;
          }
      }
  }

  free(I);
  free(J);
  free(c);
#ifdef GPU
  CUDA_SAFE_CALL(cudaFree(C_cuda));
  CUDA_SAFE_CALL(cudaFree(J_cuda));
  CUDA_SAFE_CALL(cudaFree(E_C));
  CUDA_SAFE_CALL(cudaFree(W_C));
  CUDA_SAFE_CALL(cudaFree(N_C));
  CUDA_SAFE_CALL(cudaFree(S_C));
#endif
    return kernelTime + transferTime;
}

#endif //GRID_SYNC

void random_matrix(float *I, int rows, int cols) {
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      I[i * cols + j] = rand() / (float)RAND_MAX;
    }
  }
}

