// Copyright (c) 2018-2020, Michael P. Howard
// Copyright (c) 2021-2022, Auburn University
// This file is part of the azplugins project, released under the Modified BSD License.

// Maintainer: astatt


#ifndef MPCD_COSINE_CHANNEL_FILLER_GPU_CUH_
#define MPCD_COSINE_CHANNEL_FILLER_GPU_CUH_

/*!
 * \file CosineChannelFillerGPU.cuh
 * \brief Declaration of CUDA kernels for mpcd::CosineChannelFillerGPU
 */

#include <cuda_runtime.h>

#include "CosineChannelGeometry.h"
#include "hoomd/HOOMDMath.h"
#include "hoomd/BoxDim.h"

namespace hoomd
{
namespace mpcd
{
namespace gpu
{

//! Draw virtual particles in the SineGeometry
cudaError_t sin_channel_draw_particles(Scalar4 *d_pos,
                                       Scalar4 *d_vel,
                                       unsigned int *d_tag,
                                       const mpcd::detail::SinusoidalChannel& geom,
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
                                       const uint16_t seed,
                                       const unsigned int block_size);

} // end namespace gpu
} // end namespace mpcd
} // end namespace hoomd

#endif // MPCD_COSINE_CHANNEL_FILLER_GPU_CUH_
