/***********************************************************************************
  Implementing Breadth first search on CUDA using algorithm given in HiPC'07
  paper "Accelerating Large Graph Algorithms on the GPU using CUDA"

  Copyright (c) 2008 International Institute of Information Technology - Hyderabad. 
  All rights reserved.

  Permission to use, copy, modify and distribute this software and its documentation for 
  educational purpose is hereby granted without fee, provided that the above copyright 
  notice and this permission notice appear in all copies of this software and that you do 
  not sell the software.

  THE SOFTWARE IS PROVIDED "AS IS" AND WITHOUT WARRANTY OF ANY KIND,EXPRESS, IMPLIED OR 
  OTHERWISE.

  Created by Pawan Harish.
 ************************************************************************************/
#include <stdlib.h>
#include <stdio.h>
#include <string>
#include <cassert>
#include <math.h>
#include <cuda.h>

#include "cudacommon.h"
#include "ResultDatabase.h"
#include "OptionParser.h"

#define MIN_NODES 20
#define MAX_NODES ULONG_MAX
#define MIN_EDGES 2
#define MAX_INIT_EDGES 4 // Nodes will have, on average, 2*MAX_INIT_EDGES edges
#define MIN_WEIGHT 1
#define MAX_WEIGHT 10
#define SEED 7

#define MAX_THREADS_PER_BLOCK 256

using namespace std;

struct Node
{
	int starting;
	int no_of_edges;
};

void initGraph(OptionParser &op, int &no_of_nodes, int &edge_list_size, int &source, Node* &h_graph_nodes, int* &h_graph_edges);
float BFSGraph(ResultDatabase &resultDB, OptionParser &op, int no_of_nodes, int edge_list_size, int source, Node* &h_graph_nodes, int* &h_graph_edges);
#ifdef UNIFIED_MEMORY
float BFSGraphUnifiedMemory(ResultDatabase &resultDB, OptionParser &op, int no_of_nodes, int edge_list_size, int source, Node* &h_graph_nodes, int* &h_graph_edges);
#endif

////////////////////////////////////////////////////////////////////////////////
__global__ void Kernel( Node* g_graph_nodes, int* g_graph_edges, bool* g_graph_mask, bool* g_updating_graph_mask, bool *g_graph_visited, int* g_cost, int no_of_nodes) 
{
	int tid = (blockIdx.x*MAX_THREADS_PER_BLOCK) + threadIdx.x;
	if( tid<no_of_nodes && g_graph_mask[tid])
	{
		g_graph_mask[tid]=false;
		for(int i=g_graph_nodes[tid].starting; i<(g_graph_nodes[tid].no_of_edges + g_graph_nodes[tid].starting); i++)
			{
			int id = g_graph_edges[i];
			if(!g_graph_visited[id])
				{
				g_cost[id]=g_cost[tid]+1;
				g_updating_graph_mask[id]=true;
				}
			}
	}
}

__global__ void Kernel2( bool* g_graph_mask, bool *g_updating_graph_mask, bool* g_graph_visited, bool *g_over, int no_of_nodes)
{
	int tid = (blockIdx.x*MAX_THREADS_PER_BLOCK) + threadIdx.x;
	if( tid<no_of_nodes && g_updating_graph_mask[tid])
	{

		g_graph_mask[tid]=true;
		g_graph_visited[tid]=true;
		*g_over=true;
		g_updating_graph_mask[tid]=false;
	}
}
////////////////////////////////////////////////////////////////////////////////

// ****************************************************************************
// Function: addBenchmarkSpecOptions
//
// Purpose:
//   Add benchmark specific options parsing
//
// Arguments:
//   op: the options parser / parameter database
//
// Returns:  nothing
//
// Programmer: Kyle Spafford
// Creation: August 13, 2009
//
// Modifications:
//
// ****************************************************************************
void addBenchmarkSpecOptions(OptionParser &op) {
}

// ****************************************************************************
// Function: RunBenchmark
//
// Purpose:
//   Executes the radix sort benchmark
//
// Arguments:
//   resultDB: results from the benchmark are stored in this db
//   op: the options parser / parameter database
//
// Returns:  nothing, results are stored in resultDB
//
// Programmer: Kyle Spafford
// Creation: August 13, 2009
//
// Modifications:
//
// ****************************************************************************
void RunBenchmark(ResultDatabase &resultDB, OptionParser &op) {
    int device;
    cudaGetDevice(&device);
    cudaDeviceProp deviceProp;
    cudaGetDeviceProperties(&deviceProp, device);

    // seed random number generator
	srand(SEED);

    int no_of_nodes = 0;
    int edge_list_size = 0;
    int source = 0;
	Node* h_graph_nodes;
	int* h_graph_edges;
    initGraph(op, no_of_nodes, edge_list_size, source, h_graph_nodes, h_graph_edges);

    // atts string for result database
    char tmp[64];
    sprintf(tmp, "%dV,%dE", no_of_nodes, edge_list_size);
    string atts = string(tmp);

    bool quiet = op.getOptionBool("quiet");
    int passes = op.getOptionInt("passes");
    for(int i = 0; i < passes; i++) {
        if(!quiet) {
            printf("Pass %d:\n", i);
        }
        float time = BFSGraph(resultDB, op, no_of_nodes, edge_list_size, source, h_graph_nodes, h_graph_edges);
        if(!quiet) {
            if(time == FLT_MAX) {
                printf("Executing BFS...Error.\n");
            } else {
                printf("Executing BFS...Done.\n");
            }
        }
#ifdef UNIFIED_MEMORY
        float timeUM = BFSGraphUnifiedMemory(resultDB, op, no_of_nodes, edge_list_size, source, h_graph_nodes, h_graph_edges);
        if(!quiet) {
            if(timeUM == FLT_MAX) {
                printf("Executing BFS using unified memory...Error.\n");
            } else {
                printf("Executing BFS using unified memory...Done.\n");
            }
        }
        if(time != FLT_MAX && timeUM != FLT_MAX) {
            resultDB.AddResult("BFS_Time/BFS_UM_Time", atts, "N", time/timeUM);
        }
#endif
    }

	free( h_graph_nodes);
	free( h_graph_edges);
}

////////////////////////////////////////////////////////////////////////////////
//Generate uniform distribution
////////////////////////////////////////////////////////////////////////////////
int uniform_distribution(int rangeLow, int rangeHigh) {
    double myRand = rand()/(1.0 + RAND_MAX); 
    int range = rangeHigh - rangeLow + 1;
    int myRand_scaled = (myRand * range) + rangeLow;
    return myRand_scaled;
}

////////////////////////////////////////////////////////////////////////////////
//Initialize Graph
////////////////////////////////////////////////////////////////////////////////
void initGraph(OptionParser &op, int &no_of_nodes, int &edge_list_size, int &source, Node* &h_graph_nodes, int* &h_graph_edges) {
    bool quiet = op.getOptionBool("quiet");
    // open input file for reading
    FILE *fp = NULL;
    string infile = op.getOptionString("inputFile");
    if(infile != "") {
        fp = fopen(infile.c_str(),"r");
        if(!fp && !quiet)
        {
            printf("Error: Unable to read graph file %s.\n", infile.c_str());
        }
    }

    if(!quiet) {
        if(fp) {
            printf("Reading graph file\n");
        } else {
            printf("Generating graph with problem size %d\n", (int)op.getOptionInt("size"));
        }
    }

    // initialize number of nodes
    if(fp) {
	    int n = fscanf(fp,"%d",&no_of_nodes);
        assert(n == 1);
    } else {
        int problemSizes[4] = {10, 50, 100, 200};
        no_of_nodes = problemSizes[op.getOptionInt("size") - 1] * 1024 * 1024;
    }

	// initalize the nodes & number of edges
	h_graph_nodes = (Node*) malloc(sizeof(Node)*no_of_nodes);
	int start;
    int edgeno;   
    for( int i = 0; i < no_of_nodes; i++) 
    {
        if(fp) {
            int n = fscanf(fp,"%d %d",&start,&edgeno);
            assert(n == 2);
        } else {
            start = edge_list_size;
            edgeno = rand() % (MAX_INIT_EDGES - MIN_EDGES + 1) + MIN_EDGES;
        }
        h_graph_nodes[i].starting = start;
        h_graph_nodes[i].no_of_edges = edgeno;
        edge_list_size += edgeno;
    }

	// initialize the source node
    if(fp) {
	    int n = fscanf(fp,"%d",&source);
        assert(n == 1);
    } else {
        source = uniform_distribution(0, no_of_nodes - 1);
    }
    source = 0;

    if(fp) {
        int edges;
        int n = fscanf(fp,"%d",&edges);
        assert(n == 1);
        assert(edges == edge_list_size);
    }

    // initialize the edges
	int id;
    int cost;
	h_graph_edges = (int*) malloc(sizeof(int)*edge_list_size);
	for(int i=0; i < edge_list_size ; i++)
	{
        if(fp) {
            int n = fscanf(fp,"%d %d",&id, &cost);
            assert(n == 2);
        } else {
			id = uniform_distribution(0, no_of_nodes - 1);
			//cost = rand() % (MAX_WEIGHT - MIN_WEIGHT + 1) + MIN_WEIGHT;
        }
		h_graph_edges[i] = id;
	}

    if(!quiet) {
        if(fp) {
            fclose(fp);    
            printf("Done reading graph file\n");
        } else {
            printf("Done generating graph\n");
        }
        printf("Graph size: %d nodes, %d edges\n", no_of_nodes, edge_list_size);
    }
}

////////////////////////////////////////////////////////////////////////////////
//Apply BFS on a Graph using CUDA
////////////////////////////////////////////////////////////////////////////////
float BFSGraph(ResultDatabase &resultDB, OptionParser &op, int no_of_nodes, int edge_list_size, int source, Node* &h_graph_nodes, int* &h_graph_edges) 
{
    bool verbose = op.getOptionBool("verbose");

	int num_of_blocks = 1;
	int num_of_threads_per_block = no_of_nodes;
	//Make execution Parameters according to the number of nodes
	//Distribute threads across multiple Blocks if necessary
	if(no_of_nodes>MAX_THREADS_PER_BLOCK)
	{
		num_of_blocks = (int)ceil(no_of_nodes/(double)MAX_THREADS_PER_BLOCK);
		num_of_threads_per_block = MAX_THREADS_PER_BLOCK; 
	}

	// allocate host memory
	bool *h_graph_mask = (bool*) malloc(sizeof(bool)*no_of_nodes);
	bool *h_updating_graph_mask = (bool*) malloc(sizeof(bool)*no_of_nodes);
	bool *h_graph_visited = (bool*) malloc(sizeof(bool)*no_of_nodes);

	// initalize the memory
    for( int i = 0; i < no_of_nodes; i++) 
    {
        h_graph_mask[i]=false;
        h_updating_graph_mask[i]=false;
        h_graph_visited[i]=false;
    }

	//set the source node as true in the mask
	h_graph_mask[source]=true;
	h_graph_visited[source]=true;

	// allocate mem for the result on host side
	int* h_cost = (int*) malloc( sizeof(int)*no_of_nodes);
	for(int i=0;i<no_of_nodes;i++) {
		h_cost[i]=-1;
    }
	h_cost[source]=0;

	// node list
	Node* d_graph_nodes;
	// edge list
	int* d_graph_edges;
	// mask
	bool* d_graph_mask;
	bool* d_updating_graph_mask;
	// visited nodes
	bool* d_graph_visited;
    // result
	int* d_cost;
	// bool if execution is over
	bool *d_over;

	CUDA_SAFE_CALL_NOEXIT(cudaMalloc( (void**) &d_graph_nodes, sizeof(Node)*no_of_nodes));
	CUDA_SAFE_CALL_NOEXIT(cudaMalloc( (void**) &d_graph_edges, sizeof(int)*edge_list_size));
	CUDA_SAFE_CALL_NOEXIT(cudaMalloc( (void**) &d_graph_mask, sizeof(bool)*no_of_nodes));
	CUDA_SAFE_CALL_NOEXIT(cudaMalloc( (void**) &d_updating_graph_mask, sizeof(bool)*no_of_nodes));
	CUDA_SAFE_CALL_NOEXIT(cudaMalloc( (void**) &d_graph_visited, sizeof(bool)*no_of_nodes));
	CUDA_SAFE_CALL_NOEXIT(cudaMalloc( (void**) &d_cost, sizeof(int)*no_of_nodes));
	CUDA_SAFE_CALL_NOEXIT(cudaMalloc( (void**) &d_over, sizeof(bool)));
    cudaError_t err = cudaGetLastError();
    if(err != cudaSuccess) {
        free( h_graph_mask);
        free( h_updating_graph_mask);
        free( h_graph_visited);
        free( h_cost);
        cudaFree(d_graph_nodes);
        cudaFree(d_graph_edges);
        cudaFree(d_graph_mask);
        cudaFree(d_updating_graph_mask);
        cudaFree(d_graph_visited);
        cudaFree(d_cost);  
        cudaFree(d_over);
        return FLT_MAX;
    }

    cudaEvent_t tstart, tstop;
    cudaEventCreate(&tstart);
    cudaEventCreate(&tstop);
    float elapsedTime;
double transferTime = 0.;
    cudaEventRecord(tstart, 0);
	cudaMemcpy( d_graph_nodes, h_graph_nodes, sizeof(Node)*no_of_nodes, cudaMemcpyHostToDevice) ;
	cudaMemcpy( d_graph_edges, h_graph_edges, sizeof(int)*edge_list_size, cudaMemcpyHostToDevice) ;
	cudaMemcpy( d_graph_mask, h_graph_mask, sizeof(bool)*no_of_nodes, cudaMemcpyHostToDevice) ;
	cudaMemcpy( d_updating_graph_mask, h_updating_graph_mask, sizeof(bool)*no_of_nodes, cudaMemcpyHostToDevice) ;
	cudaMemcpy( d_graph_visited, h_graph_visited, sizeof(bool)*no_of_nodes, cudaMemcpyHostToDevice) ;
	cudaMemcpy( d_cost, h_cost, sizeof(int)*no_of_nodes, cudaMemcpyHostToDevice) ;
    cudaEventRecord(tstop, 0);
    cudaEventSynchronize(tstop);
    cudaEventElapsedTime(&elapsedTime, tstart, tstop);
    transferTime += elapsedTime * 1.e-3; // convert to seconds

	// setup execution parameters
	dim3  grid( num_of_blocks, 1, 1);
	dim3  threads( num_of_threads_per_block, 1, 1);

    double kernelTime = 0;
	int k=0;
	bool stop;
	//Call the Kernel untill all the elements of Frontier are not false
	do
	{
		//if no thread changes this value then the loop stops
		stop=false;
		cudaMemcpy( d_over, &stop, sizeof(bool), cudaMemcpyHostToDevice) ;

        cudaEventRecord(tstart, 0);
        Kernel<<< grid, threads, 0 >>>( d_graph_nodes, d_graph_edges, d_graph_mask, d_updating_graph_mask, d_graph_visited, d_cost, no_of_nodes);
        cudaEventRecord(tstop, 0);
        cudaEventSynchronize(tstop);
        cudaEventElapsedTime(&elapsedTime, tstart, tstop);
        kernelTime += elapsedTime * 1.e-3;
        CHECK_CUDA_ERROR();

        // check if kernel execution generated an error
        cudaEventRecord(tstart, 0);
        Kernel2<<< grid, threads, 0 >>>( d_graph_mask, d_updating_graph_mask, d_graph_visited, d_over, no_of_nodes);
        cudaEventRecord(tstop, 0);
        cudaEventSynchronize(tstop);
        cudaEventElapsedTime(&elapsedTime, tstart, tstop);
        kernelTime += elapsedTime * 1.e-3;
        CHECK_CUDA_ERROR()

        cudaMemcpy( &stop, d_over, sizeof(bool), cudaMemcpyDeviceToHost) ;

		k++;
	}
	while(stop);

    if(verbose) {
	    printf("Kernel Executed %d times\n",k);
    }

	// copy result from device to host
    cudaEventRecord(tstart, 0);
	cudaMemcpy( h_cost, d_cost, sizeof(int)*no_of_nodes, cudaMemcpyDeviceToHost) ;
    cudaEventRecord(tstop, 0);
    cudaEventSynchronize(tstop);
    cudaEventElapsedTime(&elapsedTime, tstart, tstop);
    transferTime += elapsedTime * 1.e-3; // convert to seconds

	//Store the result into a file
    string outfile = op.getOptionString("outputFile");
    if(outfile != "") {
        FILE *fpo = fopen(outfile.c_str(),"w");
        for(int i=0;i<no_of_nodes;i++) {
            fprintf(fpo,"%d) cost:%d\n",i,h_cost[i]);
        }
        fclose(fpo);
    }

	// cleanup memory
	free( h_graph_mask);
	free( h_updating_graph_mask);
	free( h_graph_visited);
	free( h_cost);
	cudaFree(d_graph_nodes);
	cudaFree(d_graph_edges);
	cudaFree(d_graph_mask);
	cudaFree(d_updating_graph_mask);
	cudaFree(d_graph_visited);
	cudaFree(d_cost);  
    cudaFree(d_over);

    char tmp[64];
    sprintf(tmp, "%dV,%dE", no_of_nodes, edge_list_size);
    string atts = string(tmp);
    resultDB.AddResult("BFS-TransferTime", atts, "sec", transferTime);
    resultDB.AddResult("BFS-KernelTime", atts, "sec", kernelTime);
    resultDB.AddResult("BFS-TotalTime", atts, "sec", transferTime + kernelTime);
    resultDB.AddResult("BFS-Rate_Nodes", atts, "Nodes/s", no_of_nodes/kernelTime);
    resultDB.AddResult("BFS-Rate_Edges", atts, "Edges/s", edge_list_size/kernelTime);
    resultDB.AddResult("BFS-Rate_Parity", atts, "N", transferTime / kernelTime);
    return transferTime + kernelTime;
}

#ifdef UNIFIED_MEMORY
////////////////////////////////////////////////////////////////////////////////
//Apply BFS on a Graph using CUDA and Unified Memory
////////////////////////////////////////////////////////////////////////////////
float BFSGraphUnifiedMemory(ResultDatabase &resultDB, OptionParser &op, int no_of_nodes, int edge_list_size, int source, Node* &h_graph_nodes, int* &h_graph_edges) {
    bool verbose = op.getOptionBool("verbose");
    bool quiet = op.getOptionBool("quiet");

	int num_of_blocks = 1;
	int num_of_threads_per_block = no_of_nodes;
	//Make execution Parameters according to the number of nodes
	//Distribute threads across multiple Blocks if necessary
	if(no_of_nodes>MAX_THREADS_PER_BLOCK)
	{
		num_of_blocks = (int)ceil(no_of_nodes/(double)MAX_THREADS_PER_BLOCK);
		num_of_threads_per_block = MAX_THREADS_PER_BLOCK; 
	}

    // copy graph nodes to unified memory
    Node* graph_nodes;
    CUDA_SAFE_CALL(cudaMallocManaged(&graph_nodes, sizeof(Node)*no_of_nodes));
    memcpy(graph_nodes, h_graph_nodes, sizeof(Node)*no_of_nodes);

    // copy graph edges to unified memory
    int* graph_edges;
    CUDA_SAFE_CALL(cudaMallocManaged(&graph_edges, sizeof(int)*edge_list_size));
    memcpy(graph_edges, h_graph_edges, sizeof(int)*edge_list_size);

	// allocate and initalize the memory
    bool* graph_mask;
    bool* updating_graph_mask;
    bool* graph_visited;
    CUDA_SAFE_CALL(cudaMallocManaged(&graph_mask, sizeof(bool)*no_of_nodes));
    CUDA_SAFE_CALL(cudaMallocManaged(&updating_graph_mask, sizeof(bool)*no_of_nodes));
    CUDA_SAFE_CALL(cudaMallocManaged(&graph_visited, sizeof(bool)*no_of_nodes));
    cudaError_t err = cudaGetLastError();
    for( int i = 0; i < no_of_nodes; i++) 
    {
        graph_mask[i]=false;
        updating_graph_mask[i]=false;
        graph_visited[i]=false;
    }

	//set the source node as true in the mask
	graph_mask[source]=true;
	graph_visited[source]=true;

    // allocate and initialize memory for result
    int* cost;
    CUDA_SAFE_CALL(cudaMallocManaged(&cost, sizeof(int)*no_of_nodes));
    if(err != cudaSuccess) {
        cudaFree(graph_nodes);
        cudaFree(graph_edges);
        cudaFree(graph_mask);
        cudaFree(updating_graph_mask);
        cudaFree(graph_visited);
        cudaFree(cost);
        return FLT_MAX;
    }

	for(int i=0;i<no_of_nodes;i++) {
		cost[i]=-1;
    }
	cost[source]=0;

	// bool if execution is over
    bool* over;
    CUDA_SAFE_CALL(cudaMallocManaged(&over, sizeof(bool)));

    // events for timing
    cudaEvent_t tstart, tstop;
    cudaEventCreate(&tstart);
    cudaEventCreate(&tstop);
    float elapsedTime;

	// setup execution parameters
	dim3  grid( num_of_blocks, 1, 1);
	dim3  threads( num_of_threads_per_block, 1, 1);

    double kernelTime = 0;
	int k=0;
    bool stop;
	//Call the Kernel until all the elements of Frontier are not false
	do
	{
        stop = false;
        *over = stop;

        cudaEventRecord(tstart, 0);
        Kernel<<< grid, threads, 0 >>>(graph_nodes, graph_edges, graph_mask, updating_graph_mask, graph_visited, cost, no_of_nodes);
        cudaEventRecord(tstop, 0);
        cudaEventSynchronize(tstop);
        cudaEventElapsedTime(&elapsedTime, tstart, tstop);
        kernelTime += elapsedTime * 1.e-3;
        CHECK_CUDA_ERROR();

        // check if kernel execution generated an error
        cudaEventRecord(tstart, 0);
        Kernel2<<< grid, threads, 0 >>>(graph_mask, updating_graph_mask, graph_visited, over, no_of_nodes);
        cudaEventRecord(tstop, 0);
        cudaEventSynchronize(tstop);
        cudaEventElapsedTime(&elapsedTime, tstart, tstop);
        kernelTime += elapsedTime * 1.e-3;
        CHECK_CUDA_ERROR()

        stop = *over;
		k++;
	}
	while(stop);

    if(verbose && !quiet) {
        printf("Kernel Time: %f\n", kernelTime);
        printf("Kernel Executed %d times\n",k);
    }

    // cleanup memory
	cudaFree(graph_nodes);
	cudaFree(graph_edges);
	cudaFree(graph_mask);
	cudaFree(updating_graph_mask);
	cudaFree(graph_visited);
	cudaFree(cost);
    cudaFree(over);

    char tmp[64];
    sprintf(tmp, "%dV,%dE", no_of_nodes, edge_list_size);
    string atts = string(tmp);
    resultDB.AddResult("BFS-UM-TotalTime", atts, "sec", kernelTime);
    resultDB.AddResult("BFS-UM-Rate_Nodes", atts, "Nodes/s", no_of_nodes/kernelTime);
    resultDB.AddResult("BFS-UM-Rate_Edges", atts, "Edges/s", edge_list_size/kernelTime);
    return kernelTime;
}
#endif
