// Copyright (c) 2018-2020, Michael P. Howard
// Copyright (c) 2021-2022, Auburn University



#ifndef MPCD_COSINE_EXPANSION_CONSTRICTION_FILLER_GPU_CUH_
#define MPCD_COSINE_EXPANSION_CONSTRICTION_FILLER_GPU_CUH_

/*!
 * \file CosineExpansionContractionFillerGPU.cuh
 * \brief Declaration of CUDA kernels for mpcd::CosineExpansionContractionFillerGPU
 */

#include <cuda_runtime.h>

#include "CosineExpansionContractionGeometry.h"
#include "hoomd/HOOMDMath.h"
#include "hoomd/BoxDim.h"

namespace hoomd
{
namespace mpcd
{
namespace gpu
{

//! Draw virtual particles in the CoineGeometry
cudaError_t cosine_expansion_contraction_draw_particles(Scalar4 *d_pos,
                                                      Scalar4 *d_vel,
                                                      unsigned int *d_tag,
                                                      const azplugins::detail::SinusoidalExpansionConstriction& geom,
                                                      const Scalar pi_period_div_L,
                                                      const Scalar amplitude,
                                                      const Scalar H_narrow,
                                                      const Scalar thickness,
                                                      const BoxDim& box,
                                                      const Scalar mass,
                                                      const unsigned int type,
                                                      const unsigned int N_fill,
                                                      const unsigned int first_tag,
                                                      const unsigned int first_idx,
                                                      const Scalar kT,
                                                      const uint64_t timestep,
                                                      const uints16_t seed,
                                                      const unsigned int block_size);

} // end namespace gpu
} // end namespace mpcd
} // end namespace azplugins

#endif // MPCD_COSINE_EXPANSION_CONSTRICTION_FILLER_GPU_CUH_
