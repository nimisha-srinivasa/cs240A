/* Compute the SVD of a matrix */

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
// #define ROWS 31568
// #define COLS 51
#define ROWS 6
#define COLS 3
#define FILENAME "data.txt"
#define MIN(x, y) (((x) < (y)) ? (x) : (y))
#define N_ITER 1

#include <cuda_runtime.h>
#include <cublas_v2.h>
#include <cusolverDn.h>

void fill(float *p, int n) {
    // This will be replaced by retrieving the data...
    for (int i = 0; i < n; i++) {
        p[i] = (float) (2.0*drand48() + 1.0);
    }
}

void print_matrix(int m, int n, float *A, int lda, const char *name) {
    printf("================A===============================\n");
    for(int row = 0; row < m; row++) {
        for(int col = 0; col < n; col++) {
            float Areg = A[row + col*lda];
            printf("%f\t", Areg);
        }
        printf("\n");
    }
    printf("================end of A===============================\n");
}

void readMatrixFromFile(float *p, int lda){
    FILE *myFile;
    char *filename=FILENAME;
    myFile = fopen(filename, "r");
    if (myFile == NULL)
    {
        printf("Error Reading File\n");
        exit (0);
    }

    char *line=NULL;
    char *word=NULL;
    float attr;
    size_t len = 0;
    ssize_t read;
    int row,col;

    //fill the matrix
    row=0;
    while (((read = getline(&line, &len, myFile)) != -1) && row<ROWS) {
        col=0;
        do{
            word=strsep(&line,",");
            attr = atof(word);
            p[row + col*lda]=attr;
            col++;
        }while(line!=NULL && word!=NULL && col<COLS);
        row++;        
    }  
}

int main(int argc, char *argv[])
{
    
    printf("with my modifications \n");
    cusolverDnHandle_t cudenseH = NULL;

    cusolverStatus_t cusolver_status = CUSOLVER_STATUS_SUCCESS;
    cudaError_t cudaStat1 = cudaSuccess; 
    cudaError_t cudaStat2 = cudaSuccess; 
    cudaError_t cudaStat3 = cudaSuccess;
    cudaError_t cudaStat4 = cudaSuccess; 

    /*used for timing purposes*/
    cudaEvent_t start, stop;
    float time;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    
    int lwork = 0;
    int info_gpu = 0;

    // Matrix definitions
    const int rows = ROWS;
    const int cols = COLS;
    const int mat_A_size = rows*cols;
    const int mat_S_size = MIN(rows,cols);
    const int mat_U_size = rows*rows;
    const int mat_VT_size = cols*cols;
    size_t size_A = mat_A_size*sizeof(float);
    size_t size_S = mat_S_size*sizeof(float);
    size_t size_U = mat_U_size*sizeof(float);
    size_t size_VT = mat_VT_size*sizeof(float);

    float *h_A = (float*)malloc(size_A);
    float *h_S = (float*)malloc(size_S);
    float *h_U = (float*)malloc(size_U);
    float *h_VT = (float*)malloc(size_VT);
    float *d_work = NULL;
    float *rwork = NULL;

    fill(h_A, mat_A_size);
    //readMatrixFromFile(h_A, rows);


    printf("A\n");
    print_matrix(rows, cols, h_A, rows, "A");
    printf("\n\n\n");



    // Create data structures for device
    cusolver_status = cusolverDnCreate(&cudenseH);
    assert (cusolver_status == CUSOLVER_STATUS_SUCCESS);

    float* d_A = NULL;
    cudaStat1 = cudaMalloc((void**)&d_A, size_A);
    assert(cudaSuccess == cudaStat1);

    float* d_S = NULL;
    cudaStat2 = cudaMalloc((void**)&d_S, size_S);
    assert(cudaSuccess == cudaStat2);

    float* d_U = NULL;
    cudaStat3 = cudaMalloc((void**)&d_U, size_U);
    assert(cudaSuccess == cudaStat3);

    float* d_VT = NULL;
    cudaStat4 = cudaMalloc((void**)&d_VT, size_VT);
    assert(cudaSuccess == cudaStat4);

    int *devInfo = NULL; // info in gpu (device copy)
    cudaStat4 = cudaMalloc((void**)&devInfo, sizeof(int));
    assert(cudaSuccess == cudaStat4);

    /* copy data to device */
    cudaStat1 = cudaMemcpy(d_A, h_A, size_A, cudaMemcpyHostToDevice);
    assert(cudaSuccess == cudaStat1);

    /*================SOLVE FOR QR======================== */
    int qr_Lwork = 0;
    cusolver_status = cusolverDnSgeqrf_bufferSize(
            cudenseH,
            rows,
            cols,
            d_A,
            rows,
            &qr_Lwork);
    assert(cusolver_status == CUSOLVER_STATUS_SUCCESS);

    float *qr_d_work = NULL;
    float *qr_d_tau = NULL;
    int *qr_devInfo = NULL;
    cudaStat1 = cudaMalloc((void**)&qr_d_work, sizeof(float)*qr_Lwork);
    cudaStat2 = cudaMalloc((void**)&qr_d_tau, sizeof(float)*cols);
    assert(cudaStat1 == cudaSuccess);
    assert(cudaStat2 == cudaSuccess);

    cusolver_status = cusolverDnSgeqrf(
            cudenseH,
            rows,
            cols,
            d_A,
            rows,
            qr_d_tau,
            qr_d_work,
            qr_Lwork,
            qr_devInfo);

    /* Bring ``A'' back to device to get R */
    cudaStat1 = cudaMemcpy(h_A, d_A, size_A, cudaMemcpyDeviceToHost);
    assert(cudaSuccess == cudaStat1);
    assert(qr_devInfo == 0);

    printf("New A\n");
    print_matrix(rows, cols, h_A, rows, "A");
    printf("\n\n\n");

    float *h_R = NULL;
    float *d_R = NULL;
    const int mat_R_size = cols*cols;
    size_t size_R = mat_R_size*sizeof(float);
    h_R = (float*)malloc(size_R);

    /* Fill up R */
    for(int i = 0; i < rows; i++) {
        for(int j = 0; j < cols; j++) {
            if(i <= j)
                h_R[i + j*cols] = h_A[i + j*cols];
            else
                h_R[i + j*cols] = 0.0;
        }
    }


    printf("R\n");
    print_matrix(cols, cols, h_R, cols, "R");
    printf("\n\n\n");

    /*================SOLVE FOR SVD======================= */

    /* calculate the sizes needed for pre-allocated buffer Lwork  */
    cusolver_status = cusolverDnSgesvd_bufferSize(cudenseH, rows, cols, &lwork );
    assert (cusolver_status == CUSOLVER_STATUS_SUCCESS);
    printf("lwork/buffer size=%d\n",lwork);

    /* allocate memory for buffer */
    cudaStat1 = cudaMalloc((void**)&d_work, sizeof(float)*lwork);
    assert(cudaSuccess == cudaStat1);
    cudaStat2 = cudaMalloc((void**)&rwork, sizeof(float)*lwork);
    assert(cudaSuccess == cudaStat2);

    /* computer SVD */
    char jobu = 'A'; // We do not want/need U
    char jobvt = 'A'; // We want all the vectors of VT
    int lda = rows;
    int ldu = rows;
    int ldvt = cols;
    
    /* printf("with  allocating memory for rwork!\n");*/
    cudaEventRecord(start, 0);


    int n_iterations = N_ITER;
    for(int i = 0; i < n_iterations; i++) {
        cusolver_status = cusolverDnSgesvd (cudenseH, jobu, jobvt, rows, cols, d_A, lda, d_S, d_U, ldu, d_VT, ldvt, d_work, lwork, rwork, devInfo);
        cudaStat1 = cudaDeviceSynchronize();
    }




    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);
    assert(cudaSuccess == cudaStat1);
    printf("cusolverDnSgesvd status :\t");
    switch(cusolver_status)
      {
        case CUSOLVER_STATUS_SUCCESS:
          printf("success\n");
          break;
        case CUSOLVER_STATUS_NOT_INITIALIZED :
          printf("Library cuSolver not initialized correctly\n");
          break;
        case CUSOLVER_STATUS_INVALID_VALUE:
          printf("Invalid parameters passed\n");
          break;
        case CUSOLVER_STATUS_INTERNAL_ERROR:
          printf("Internal operation failed\n");
          break;
        case CUSOLVER_STATUS_EXECUTION_FAILED:
          printf("Execution failed\n");
          break;
      }


    /* ================END of SVD Computation======================= */

    /*  check if SVD is good or not  */
    cudaStat1 =cudaMemcpy(&info_gpu,devInfo,sizeof(int),cudaMemcpyDeviceToHost);
    assert(cudaSuccess == cudaStat1);
    printf("after SVD: info_gpu = %d\n", info_gpu);
    assert(0 == info_gpu); 
    
    ///*  copy the solutions back to the host */
    cudaStat1 = cudaMemcpy(h_A, d_A, size_A, cudaMemcpyDeviceToHost);
    assert(cudaSuccess == cudaStat1);

    cudaStat1 = cudaMemcpy(h_U, d_U, size_U, cudaMemcpyDeviceToHost);
    cudaStat2 = cudaMemcpy(h_S, d_S, size_S, cudaMemcpyDeviceToHost);
    cudaStat3 = cudaMemcpy(h_U, d_U, size_VT, cudaMemcpyDeviceToHost);
    assert(cudaSuccess == cudaStat1); 
    assert(cudaSuccess == cudaStat2);
    assert(cudaSuccess == cudaStat3);

    /* 
    printf("U\n");
    print_matrix(rows, rows, h_U, rows, "A");
    printf("\n\n\n");

    printf("S\n");
    print_matrix(rows, cols, h_S, rows, "S");
    printf("\n\n\n");

    printf("VT\n");
    print_matrix(cols, cols, h_VT, cols, "VT");
    printf("\n\n\n");

     
    printf("A\n");
    print_matrix(rows, rows, h_A, rows, "A");
    printf("\n\n\n");
    */

    /* free resources */
    if (d_A ) cudaFree(d_A);
    if (d_S ) cudaFree(d_S);
    if (d_U ) cudaFree(d_U);
    if (d_VT ) cudaFree(d_VT);

    if(h_A) free(h_A);
    if(h_S) free(h_S);
    if(h_U) free(h_U);
    if(h_VT) free(h_VT);

    /*  print the time */
    cudaEventElapsedTime(&time, start, stop);
    printf ("Time for the kernel: %f ms\n", time);
    printf ("\n\n\n");

    /*  total resources and computing */
    float Mflop_rate;
    Mflop_rate = 1e-6 * 4 * rows * rows * cols * n_iterations / time;
    printf ("n_iterations = %d\n",n_iterations);
    printf ("Mflop/s: %f\n", Mflop_rate);

    if (cudenseH) cusolverDnDestroy(cudenseH);

    

    cudaDeviceReset();
}
