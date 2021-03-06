# Use this file as input to autoconf to output a configure script.

AC_PREREQ([2.65])
AC_INIT([MIROVIA], [1.0.0], [sarahgw@cs.utexas.edu])
AC_CONFIG_AUX_DIR([build-aux])
AC_CANONICAL_SYSTEM
AC_CONFIG_SRCDIR([src/common/Timer.h])
AC_CONFIG_HEADERS([config/config.h])
AM_MAINTAINER_MODE([disable])
AM_INIT_AUTOMAKE([foreign subdir-objects])

# Mirovia is a collection of C++ programs AC_LANG([C++])
AC_LANG([C++])

# Set default installation location to the build location
AC_PREFIX_DEFAULT(`pwd`)

# Check for fundamental programs.
AC_PROG_CXX
AC_PROG_CC
AC_PROG_RANLIB
AC_CHECK_TOOL([AR], [ar], [:])
AC_PATH_PROG([UNZIP], [unzip])

# Check whether special NVCXXFLAGS were specified
# If not, set default flags based on whether we're using g++ and whether our
# C++ compiler supports -g.
# Logic based on the logic used in the AC_PROG_CXX macro.
ac_save_NVCXXFLAGS=${NVCXXFLAGS}
ac_test_NVCXXFLAGS=${NVCXXFLAGS+set}
if test "$ac_test_NVCXXFLAGS" = set
then
    NVCXXFLAGS=$ac_save_NVCXXFLAGS
elif test $ac_cv_prog_cxx_g = yes
then
    if test "$GXX" = yes; then
        NVCXXFLAGS="-g -O2"
    else
        NVCXXFLAGS="-g"
    fi
else
    if test "$GXX" = yes
    then
        NVCXXFLAGS="-O2"
    else
        NVCXXFLAGS=
    fi
fi

# On Linux, clock_gettime function seems to require the rt library
AS_CASE([$host],
    [*-*-linux*], [LIBS="$LIBS -lrt"],
    [*], []
)

# Check for header files.
AC_FUNC_ALLOCA
AC_CHECK_HEADERS([float.h stdlib.h string.h sys/time.h sys/timeb.h time.h unistd.h])

# Check for typedefs, structures, and compiler characteristics.
AC_HEADER_STDBOOL
AC_C_INLINE
AC_C_RESTRICT
AC_TYPE_SIZE_T

# Check for library functions.
AC_FUNC_ERROR_AT_LINE
AC_CHECK_FUNCS([clock_gettime floor gethostname gettimeofday localtime_r memset pow sqrt strdup])

AS_IF([test "x$ac_cv_func_clock_gettime" = xyes],
    [ AC_MSG_CHECKING([whether clock_gettime() supports CLOCK_PROCESS_CPUTIME_ID timer])
      AC_LINK_IFELSE([AC_LANG_PROGRAM([],[])],
                    [AC_MSG_RESULT([yes])
                     AC_DEFINE([HAVE_CLOCK_PROCESS_CPUTIME_ID],[1],[Define to 1 if you have the CLOCK_PROCESS_CPUTIME_ID timer for the 'clock_gettime' function])
                    ],
                    [AC_MSG_RESULT([no])]
      )
    ]
)    

# CUDA support
AC_ARG_WITH([cuda],
    [AS_HELP_STRING([--with-cuda],
        [build CUDA versions of MIROVIA benchmark programs @<:@default=check@:>@])],
    [],
    [with_cuda=check])

USE_CUDA=no
AS_IF([test "x$with_cuda" != xno],
    [
        # Check for the nvcc program
        AC_PATH_PROG([NVCC],[nvcc],[])

        AS_IF([test "x$NVCC" != x], [ savedCXX=$CXX
              CXX=$NVCC
              savedLIBS=$LIBS
              savedCPPFLAGS=$CPPFLAGS
              savedCXXFLAGS=$CXXFLAGS
              savedLDFLAGS=$LDFLAGS
              CXXFLAGS=$NVCXXFLAGS
              LDFLAGS=""

              # Find cuda include path based on location of nvcc command
              cudabindir=`AS_DIRNAME([$NVCC])`
              CUDA_INCDIR=`AS_DIRNAME([$cudabindir])`/include
              CPPFLAGS="$CPPFLAGS -I$CUDA_INCDIR"

              AC_CHECK_HEADERS([cuda.h cuda_runtime.h],[],
                  [NVCC=""]
                  )
              AC_CHECK_LIB([cublas], [cublasInit],[],
                  [NVCC=""]
                  )
              AC_CHECK_LIB([cufft], [cufftPlan1d], [],
                  [NVCC=""]
                  )

              CPPFLAGS=$savedCPPFLAGS
              LIBS=$savedLIBS
              CXX=$savedCXX
              CXXFLAGS=$savedCXXFLAGS LDFLAGS=$savedLDFLAGS ],
            [ if test "x$with_cuda" != xcheck; then
                AC_MSG_FAILURE([CUDA support was requested, but no usable CUDA installation found])
              fi
              NVCC=""
            ]
        )

        AS_IF([test "x$NVCC" != x],
            [with_cuda=yes
             USE_CUDA=yes
             AC_SUBST([CUDA_INCDIR])],
            [AC_MSG_NOTICE([no usable CUDA installation found])
             with_cuda=no
            ])

        AS_IF([test "x$with_cuda" = xyes],
            [AS_IF([test "x$CUDA_CPPFLAGS" = x],
                [dnl generate CUDA code for broad spectrum of devices
                 CUDA_CPPFLAGS=["-arch=sm_60 -gencode=arch=compute_60,code=sm_60"]
                 AC_MSG_NOTICE([using CUDA_CPPFLAGS=$CUDA_CPPFLAGS])
                 AC_MSG_WARN([*** MIROVIA programs may fail if these -gencode values do not apply to your GPU.  If they don't apply, or if you want to shorten MIROVIA's compile time, determine the -gencode options that apply for your GPU and re-configure MIROVIA explicitly specifying only those options in CUDA_CPPFLAGS during the configure. ***])
                ]
             )
             AC_SUBST([CUDA_CPPFLAGS])
            ]
        )
    ]
)
AM_CONDITIONAL([BUILD_CUDA], [test "x$with_cuda" = "xyes"])

'''
# test whether or not to build new cuda features in benchmarks
unified_memory=yes
grid_sync=yes
hyperq=yes
dynamic_parallelism=yes
AS_IF([nvcc --version | grep -q "release 8"], [grid_sync=no],[])
AS_IF([nvcc --version | grep -q "release 7"], [grid_sync=no],[])
AS_IF([nvcc --version | grep -q "release 6"], [grid_sync=no],[])
AS_IF([nvcc --version | grep -q "release 5"], [grid_sync=no, unified_memory=no],[])
AS_IF([nvcc --version | grep -q "release 4"], [grid_sync=no, unified_memory=no, hyperq=no, dynamic_parallelism=no],[])
AS_IF([nvcc --version | grep -q "release 3"], [grid_sync=no, unified_memory=no, hyperq=no, dynamic_parallelism=no],[])
AS_IF([nvcc --version | grep -q "release 2"], [grid_sync=no, unified_memory=no, hyperq=no, dynamic_parallelism=no],[])
AS_IF([nvcc --version | grep -q "release 1"], [grid_sync=no, unified_memory=no, hyperq=no, dynamic_parallelism=no],[])

AS_IF([test "x$unified_memory" = "xyes"], 
        [
            AC_MSG_RESULT([supports unified memory: yes])
            CUDA_CPPFLAGS+=[" -DUNIFIED_MEMORY"]
        ],
        [
            AC_MSG_RESULT([supports unified memory: no])
        ])

AS_IF([test "x$grid_sync" = "xyes"], 
    [
        AC_MSG_RESULT([supports grid sync: yes])
        CUDA_CPPFLAGS+=[" -DGRID_SYNC"]
    ],
    [
        AC_MSG_RESULT([supports grid sync: no])
    ])

AS_IF([test "x$hyperq" = "xyes"], 
    [
        AC_MSG_RESULT([supports hyperq: yes])
        CUDA_CPPFLAGS+=[" -DHYPERQ"]
    ],
    [
        AC_MSG_RESULT([supports hyperq: no])
    ])

AS_IF([test "x$dynamic_parallelism" = "xyes"], 
    [
        AC_MSG_RESULT([supports dynamic parallelism: yes])
        CUDA_CPPFLAGS+=[" -DDYNAMIC_PARALLELISM"]
    ],
    [
        AC_MSG_RESULT([supports dynamic parallelism: no])
    ])
'''

AC_SUBST([USE_CUDA])
AC_SUBST([NVCXXFLAGS])

AC_CONFIG_FILES([Makefile
                 config/common.mk
                 config/config.mk
                 config/dirtargets.mk
                 config/targets.mk
                 src/Makefile
                 src/common/Makefile
                 src/cuda/Makefile
                 src/cuda/level0/Makefile
                 src/cuda/level0/busspeeddownload/Makefile
                 src/cuda/level0/busspeedreadback/Makefile
                 src/cuda/level0/devicememory/Makefile
                 src/cuda/level0/maxflops/Makefile
                 src/cuda/level1/Makefile
                 src/cuda/level1/bfs/Makefile
                 src/cuda/level1/gemm/Makefile
                 src/cuda/level1/pathfinder/Makefile
                 src/cuda/level1/sort/Makefile
                 src/cuda/level2/Makefile
                 src/cuda/level2/cfd/Makefile
                 src/cuda/level2/dwt2d/Makefile
                 src/cuda/level2/kmeans/Makefile
                 src/cuda/level2/lavamd/Makefile
                 src/cuda/level2/mandelbrot/Makefile
                 src/cuda/level2/neuralnet/Makefile
                 src/cuda/level2/nw/Makefile
                 src/cuda/level2/particlefilter/Makefile
                 src/cuda/level2/srad/Makefile
                 src/cuda/level2/where/Makefile
                 ])
AC_OUTPUT

