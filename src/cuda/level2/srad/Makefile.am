include $(top_builddir)/config/config.mk
include $(top_builddir)/config/targets.mk

EXTRAFLAGS = -rdc=true -dc

# How to find source files
VPATH = $(srcdir):$(srcdir)/../../common:$(srcdir)/../../../common

AM_LDFLAGS = $(CUDA_LDFLAGS)
AM_CPPFLAGS = $(CUDA_INC)

# What is the destination for programs built from this directory?
cudadir = $(bindir)/CUDA

# What programs should be installed to that destination?
cuda_PROGRAMS = srad

srad_link.o: srad.o
	$(NVCC) ${CUDA_CPPFLAGS} $(CPPFLAGS) $(NVCXXFLAGS) -dlink $< -o srad_link.o

# How to build those programs?
srad_SOURCES = \
main.cpp
srad_LDADD = \
srad.o \
srad_link.o \
$(CUDA_LIBS) $(LIBS) -lm

