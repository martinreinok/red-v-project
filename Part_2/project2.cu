#pragma optimize( "", off )


#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <memory.h>
#include <malloc.h>



// Example data to load from your file:
// 117,85,146,194,21,20,20,20,20,20,20,20,20,20,20,20,20,
// 20,20,20,20,20,20,20,21,22,417,418,141,68,196,198,194,177,
// 173,173,172,2101,172,172,173,149,172,172,172,173,172,175,
// 173,173,172,171,172,100,111,101,101,100,98,98,98,88,
// 98,99,97,98,96,96,97,98,98,96,98,98,97,98,97,97,92,96


// A few filtering kernels as samples
float low_pass_kernel[9] = {
    1.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0,
    1.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0,
    1.0 / 9.0, 1.0 / 9.0, 1.0 / 9.0
};

// float the inputs
float hor_line_kernel[9] = {
    -1.0, -1.0, -1.0,
     2.0,  2.0,  2.0,
    -1.0, -1.0, -1.0
};

float ver_line_kernel[9] = {
    -1.0, 2.0, -1.0,
    -1.0, 2.0, -1.0,
    -1.0, 2.0, -1.0
};

__constant__ float convKernal[9];

__global__ void convolution(int* distArray, float* result, int distIndex, int posIndex, int maskIndex, int calcAmount) {
    // Global thread positions
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    int row = blockIdx.y * blockDim.y + threadIdx.y;

    // Calculate radius of the mask
    int r = maskIndex / 2;

    // Calculate the start point for the element
    int startcol = col - r;
    int startrow = row - r;

    // Temp value for calculation
    float temp = 0;

    // go over each element of the mask
    for (int i = 0; i < maskIndex; i++) {
        for (int j = 0; j < maskIndex; j++) {
            if ((startrow + i) >= 0 && (startrow + i) < distIndex) {
                // range check for columns
                if ((startcol + j) >= 0 && (startcol + j) < posIndex) {
                    // Accumulate result
                    temp += convKernal[i * maskIndex + j] * distArray[(startrow + i) * posIndex + (startcol + j)];
                    result[startrow * posIndex + startcol] = temp / 255;
                }
            }         
        }
    }
    
    //    // Apply kernel for all points in the matrix
    //    for (y = 1; y < dstNum - 1; y++) {
    //        for (x = 1; x < posNum - 1; x++) {
    //            sum = 0.0;
    //            for (k = -1; k < 2; k++) {
    //                for (j = -1; j < 2; j++) {
    //                    sum += hor_line_kernel[(k + 1) * 3 + (j + 1)] * (float)distance_matrix[(y - k) * posNum + (x - j)];
    //                    //printf("y[%d] x[%d] k[%d] j[%d] | kernel[%d]: %d | matrix[%d]: %f\n", y, x, k, j, (k + 1) * 3 + (j + 1), hor_line_kernel[(k + 1) * 3 + (j + 1)], (y - k) * posNum + (x - j), distance_matrix[(y - k) * posNum + (x - j)]);
    //                }
    //            }
    //            filtered_matrix[y * posNum + x] = sum / 255;
    //        }
    //    }
    //}
}

int main(int argc, char* argv[]) {

    clock_t start, end;
    double cpu_time_used;

    if (argc < 2) {
        printf("Need 2 arguments! X(Number of positions) and Y(Max Distance)\n\n");
        return -1;
    }

    
    int posNum = atoi(argv[1]);
    int dstNum = atoi(argv[2]);
    printf("Positions: %d, Max Distance: %d\n", posNum, dstNum);

    int* distance_vector = (int*)calloc(posNum, sizeof(int));
    int* distance_matrix = (int*)calloc(posNum * dstNum, sizeof(int));
    float* filtered_matrix = (float*)calloc(posNum * dstNum, sizeof(float));
    int* threshold_matrix = (int*)calloc(posNum * dstNum, sizeof(int));
    int* new_vector = (int*)calloc(posNum, sizeof(int));

    int i;


    // Implement your LOAD_DATA function here to load X number of elements and store them into distance_vector
    int data[] = { 117,85,146,194,21,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,21,22,417,418,141,68,196,198,194,177,173,173,172,2101,172,172,173,149,172,172,172,173,172,175,173,173,172,171,172,100,111,101,101,100,98,98,98,88,98,99,97,98,96,96,97,98,98,96,98,98,97,98,97,97,92,96 };
    for (int d = 0; d < posNum; d++) {
        distance_vector[d] = data[d];
        printf("distance_vector[%d]: %d\n", d, distance_vector[d]);
    }

    // Creates matrix from input vector
    for (i = 0; i < posNum; i++) {
        int distance = distance_vector[i];
        if (distance >= dstNum) distance = dstNum - 1;
        distance_matrix[distance * posNum + i] = 255;//sets distance object
        printf("distance_matrix[%d]: %d\n", distance * posNum + i, distance_matrix[distance * posNum + i]);
    }

    // Start time measure
    start = clock();

    /******************* OPTIMIZE THIS ***********************/

    // Number of iterations of the calculations 
    int calcAmount = 1000;

    // Number of elements in indexed matrixed array
    int n = posNum * dstNum;

    // Bytes of indexed matrixed array
    int bytes_n = n * sizeof(int);

    // Bytes of output matrix array
    int bytes_out = n * sizeof(float);

    // Size of convolution mask (indexed matrix array)
    int maskIndex = 3;

    // Size of convolution mask in bytes
    int bytes_maskIndex = (maskIndex * maskIndex) * sizeof(float);

    // Allocate space on the device 
    float* d_hor_line_kernel, * d_filtered_matrix;
    int* d_distance_matrix;

    //cudaMalloc(&d_hor_line_kernel, bytes_maskIndex);
    cudaMalloc(&d_filtered_matrix, bytes_out);
    cudaMalloc(&d_distance_matrix, bytes_n);

    // Copy the data to the device
    //cudaMemcpy(d_hor_line_kernel, hor_line_kernel, bytes_maskIndex, cudaMemcpyHostToDevice);
    cudaMemcpy(d_distance_matrix, distance_matrix, bytes_n, cudaMemcpyHostToDevice);
    cudaMemcpyToSymbol(convKernal, hor_line_kernel, bytes_maskIndex);
    
    // Threads per Threadblock (TB)
    int THREADS = 16;

    // Number of Threadblocks (TB)
    int GRID = (n + THREADS - 1) / THREADS;

    // Dimension arguments
    dim3 block_dim(THREADS, THREADS);
    dim3 grid_dim(GRID, GRID);

    // Call the kernel
    convolution << <grid_dim, block_dim >> > (d_distance_matrix, d_filtered_matrix, dstNum, posNum, maskIndex, calcAmount);

    // Copy back the result
    cudaMemcpy(filtered_matrix, d_filtered_matrix, bytes_out, cudaMemcpyDeviceToHost);

    int x, y;

    //int l, j, k, x, y;
    //float sum = 0.0;

    //// Repeat 1000 times
    //for (l = 0; l < 1000; l++) {

    //    // Apply kernel for all points in the matrix
    //    for (y = 1; y < dstNum - 1; y++) {
    //        for (x = 1; x < posNum - 1; x++) {
    //            sum = 0.0;
    //            for (k = -1; k < 2; k++) {
    //                for (j = -1; j < 2; j++) {
    //                    sum += hor_line_kernel[(k + 1) * 3 + (j + 1)] * (float)distance_matrix[(y - k) * posNum + (x - j)];
    //                    //printf("y[%d] x[%d] k[%d] j[%d] | kernel[%d]: %d | matrix[%d]: %f\n", y, x, k, j, (k + 1) * 3 + (j + 1), hor_line_kernel[(k + 1) * 3 + (j + 1)], (y - k) * posNum + (x - j), distance_matrix[(y - k) * posNum + (x - j)]);
    //                }
    //            }
    //            filtered_matrix[y * posNum + x] = sum / 255;
    //        }
    //    }
    //}

    

    /********************************************************/

        // End time measure
    end = clock();
    cpu_time_used = ((double)(end - start) / 1000) / CLOCKS_PER_SEC;

    // Threshold the matrix
    for (x = 0; x < posNum; x++) {
        for (y = 0; y < dstNum; y++) {
            if (filtered_matrix[y * posNum + x] >= 4.0) {
                threshold_matrix[y * posNum + x] = 1;
            }
        }
    }

    // Extract vector from matrix
    for (x = 0; x < posNum; x++) {
        for (y = 0; y < dstNum; y++) {
            if (threshold_matrix[y * posNum + x]) {
                new_vector[x] = y;//sets distance object
            }
        }
        if (new_vector[x] == 0) new_vector[x] = 300;
    }

    // Prints threshold-filtered vector
    for (x = 0; x < posNum; x++) {
        printf("%d, ", new_vector[x]);
    }

    printf("\n Total time = %f ms\n", cpu_time_used * 1000);

    free(distance_vector);
    free(distance_matrix);
    free(filtered_matrix);
    free(threshold_matrix);
    free(new_vector);

    return 0;
}