#include "hip/hip_runtime.h"
// Copyright (c) 2009-2021 The Regents of the University of Michigan
// This file is part of the HOOMD-blue project, released under the BSD 3-Clause License.

#include "HelfrichMeshForceComputeGPU.cuh"
#include "hoomd/TextureTools.h"

#include <assert.h>

// SMALL a relatively small number
#define SMALL Scalar(0.001)

/*! \file HelfrichMeshForceComputeGPU.cu
    \brief Defines GPU kernel code for calculating the helfrich forces. Used by
   HelfrichMeshForceComputeComputeGPU.
*/

namespace hoomd
    {
namespace md
    {
namespace kernel
    {
//! Kernel for calculating helfrich sigmas on the GPU
/*! \param d_sigma Device memory to write per paricle sigma
    \param d_sigma_dash Device memory to write per particle sigma_dash
    \param N number of particles
    \param d_pos device array of particle positions
    \param d_rtag device array of particle reverse tags
    \param box Box dimensions (in GPU format) to use for periodic boundary conditions
    \param blist List of mesh bonds stored on the GPU
    \param d_triangles device array of mesh triangles
    \param n_bonds_list List of numbers of mesh bonds stored on the GPU
*/
__global__ void gpu_compute_helfrich_sigma_kernel(Scalar* d_sigma,
                                                  Scalar3* d_sigma_dash,
                                                  const unsigned int N,
                                                  const Scalar4* d_pos,
                                                  const unsigned int* d_rtag,
                                                  BoxDim box,
                                                  const group_storage<4>* blist,
                                                  const group_storage<6>* d_triangles,
                                                  const Index2D blist_idx,
                                                  const unsigned int* n_bonds_list)
    {
    // start by identifying which particle we are to handle
    int idx = blockIdx.x * blockDim.x + threadIdx.x;

    if (idx >= N)
        return;

    // load in the length of the list for this thread (MEM TRANSFER: 4 bytes)
    int n_bonds = n_bonds_list[idx];

    // read in the position of our b-particle from the a-b-c triplet. (MEM TRANSFER: 16 bytes)
    Scalar4 postype = __ldg(d_pos + idx);
    Scalar3 pos = make_scalar3(postype.x, postype.y, postype.z);

    // initialize the force to 0
    Scalar3 sigma_dash = make_scalar3(Scalar(0.0), Scalar(0.0), Scalar(0.0));

    Scalar sigma = 0.0;

    // loop over all angles
    for (int bond_idx = 0; bond_idx < n_bonds; bond_idx++)
        {
        group_storage<4> cur_bond = blist[blist_idx(idx, bond_idx)];

        int cur_bond_idx = cur_bond.idx[0];
        int cur_tr1_idx = cur_bond.idx[1];
        int cur_tr2_idx = cur_bond.idx[2];

        if (cur_tr1_idx == cur_tr2_idx)
            continue;

        const group_storage<6>& triangle1 = d_triangles[cur_tr1_idx];

        unsigned int cur_idx_c = d_rtag[triangle1.tag[0]];

        unsigned int iterator = 1;
        while (idx == cur_idx_c || cur_bond_idx == cur_idx_c)
            {
            cur_idx_c = d_rtag[triangle1.tag[iterator]];
            iterator++;
            }

        const group_storage<6>& triangle2 = d_triangles[cur_tr2_idx];

        unsigned int cur_idx_d = d_rtag[triangle2.tag[0]];

        iterator = 1;
        while (idx == cur_idx_d || cur_bond_idx == cur_idx_d)
            {
            cur_idx_d = d_rtag[triangle2.tag[iterator]];
            iterator++;
            }

        // get the b-particle's position (MEM TRANSFER: 16 bytes)
        Scalar4 bb_postype = d_pos[cur_bond_idx];
        Scalar3 bb_pos = make_scalar3(bb_postype.x, bb_postype.y, bb_postype.z);
        // get the c-particle's position (MEM TRANSFER: 16 bytes)
        Scalar4 cc_postype = d_pos[cur_idx_c];
        Scalar3 cc_pos = make_scalar3(cc_postype.x, cc_postype.y, cc_postype.z);
        // get the c-particle's position (MEM TRANSFER: 16 bytes)
        Scalar4 dd_postype = d_pos[cur_idx_d];
        Scalar3 dd_pos = make_scalar3(dd_postype.x, dd_postype.y, dd_postype.z);

        Scalar3 dab = bb_pos - pos;
        Scalar3 dac = cc_pos - pos;
        Scalar3 dad = dd_pos - pos;
        Scalar3 dbc = cc_pos - bb_pos;
        Scalar3 dbd = dd_pos - bb_pos;

        dab = box.minImage(dab);
        dac = box.minImage(dac);
        dad = box.minImage(dad);
        dbc = box.minImage(dbc);
        dbd = box.minImage(dbd);

        // on paper, the formula turns out to be: F = K*\vec{r} * (r_0/r - 1)
        // FLOPS: 14 / MEM TRANSFER: 2 Scalars

        // FLOPS: 42 / MEM TRANSFER: 6 Scalars
        Scalar rsqab = dab.x * dab.x + dab.y * dab.y + dab.z * dab.z;
        Scalar rac = dac.x * dac.x + dac.y * dac.y + dac.z * dac.z;
        rac = sqrt(rac);
        Scalar rad = dad.x * dad.x + dad.y * dad.y + dad.z * dad.z;
        rad = sqrt(rad);

        Scalar rbc = dbc.x * dbc.x + dbc.y * dbc.y + dbc.z * dbc.z;
        rbc = sqrt(rbc);
        Scalar rbd = dbd.x * dbd.x + dbd.y * dbd.y + dbd.z * dbd.z;
        rbd = sqrt(rbd);

        Scalar3 nac, nad, nbc, nbd;
        nac = dac / rac;
        nad = dad / rad;
        nbc = dbc / rbc;
        nbd = dbd / rbd;

        Scalar c_accb = nac.x * nbc.x + nac.y * nbc.y + nac.z * nbc.z;

        if (c_accb > 1.0)
            c_accb = 1.0;
        if (c_accb < -1.0)
            c_accb = -1.0;

        Scalar s_accb = sqrt(1.0 - c_accb * c_accb);
        if (s_accb < SMALL)
            s_accb = SMALL;
        s_accb = 1.0 / s_accb;

        Scalar c_addb = nad.x * nbd.x + nad.y * nbd.y + nad.z * nbd.z;

        if (c_addb > 1.0)
            c_addb = 1.0;
        if (c_addb < -1.0)
            c_addb = -1.0;

        Scalar s_addb = sqrt(1.0 - c_addb * c_addb);
        if (s_addb < SMALL)
            s_addb = SMALL;
        s_addb = 1.0 / s_addb;

        Scalar cot_accb = c_accb * s_accb;
        Scalar cot_addb = c_addb * s_addb;

        Scalar sigma_hat_ab = (cot_accb + cot_addb) / 2;

        Scalar sigma_a = sigma_hat_ab * rsqab * 0.25;

        Scalar3 sigma_dash_a = sigma_hat_ab * dab;

        sigma += sigma_a;
        sigma_dash += sigma_dash_a;
        }

    // now that the force calculation is complete, write out the result (MEM TRANSFER: 20 bytes)
    d_sigma[idx] = sigma;
    d_sigma_dash[idx] = sigma_dash;
    }

/*! \param d_sigma Device memory to write per paricle sigma
    \param d_sigma_dash Device memory to write per particle sigma_dash
    \param N number of particles
    \param d_pos device array of particle positions
    \param d_rtag device array of particle reverse tags
    \param box Box dimensions (in GPU format) to use for periodic boundary conditions
    \param blist List of mesh bonds stored on the GPU
    \param d_triangles device array of mesh triangles
    \param n_bonds_list List of numbers of mesh bonds stored on the GPU
    \param block_size Block size to use when performing calculations
    \param compute_capability Device compute capability (200, 300, 350, ...)

    \returns Any error code resulting from the kernel launch
    \note Always returns hipSuccess in release builds to avoid the hipDeviceSynchronize()
*/
hipError_t gpu_compute_helfrich_sigma(Scalar* d_sigma,
                                      Scalar3* d_sigma_dash,
                                      const unsigned int N,
                                      const Scalar4* d_pos,
                                      const unsigned int* d_rtag,
                                      const BoxDim& box,
                                      const group_storage<4>* blist,
                                      const group_storage<6>* d_triangles,
                                      const Index2D blist_idx,
                                      const unsigned int* n_bonds_list,
                                      int block_size)
    {
    unsigned int max_block_size;
    hipFuncAttributes attr;
    hipFuncGetAttributes(&attr, (const void*)gpu_compute_helfrich_sigma_kernel);
    max_block_size = attr.maxThreadsPerBlock;

    unsigned int run_block_size = min(block_size, max_block_size);

    // setup the grid to run the kernel
    dim3 grid(N / run_block_size + 1, 1, 1);
    dim3 threads(run_block_size, 1, 1);

    // run the kernel
    hipLaunchKernelGGL((gpu_compute_helfrich_sigma_kernel),
                       dim3(grid),
                       dim3(threads),
                       0,
                       0,
                       d_sigma,
                       d_sigma_dash,
                       N,
                       d_pos,
                       d_rtag,
                       box,
                       blist,
                       d_triangles,
                       blist_idx,
                       n_bonds_list);

    return hipSuccess;
    }

//! Kernel for calculating helfrich sigmas on the GPU
/*! \param d_force Device memory to write computed forces
    \param d_virial Device memory to write computed virials
    \param virial_pitch
    \param N number of particles
    \param d_pos device array of particle positions
    \param d_rtag device array of particle reverse tags
    \param box Box dimensions (in GPU format) to use for periodic boundary conditions
    \param d_sigma Device memory to write per paricle sigma
    \param d_sigma_dash Device memory to write per particle sigma_dash
    \param blist List of mesh bonds stored on the GPU
    \param d_triangles device array of mesh triangles
    \param n_bonds_list List of numbers of mesh bonds stored on the GPU
    \param d_params K params packed as Scalar variables
    \param n_bond_type number of mesh bond types
    \param d_flags Flag allocated on the device for use in checking for bonds that cannot be
*/
__global__ void gpu_compute_helfrich_force_kernel(Scalar4* d_force,
                                                  Scalar* d_virial,
                                                  const size_t virial_pitch,
                                                  const unsigned int N,
                                                  const Scalar4* d_pos,
                                                  const unsigned int* d_rtag,
                                                  BoxDim box,
                                                  const Scalar* d_sigma,
                                                  const Scalar3* d_sigma_dash,
                                                  const group_storage<4>* blist,
                                                  const group_storage<6>* d_triangles,
                                                  const Index2D blist_idx,
                                                  const unsigned int* n_bonds_list,
                                                  Scalar* d_params,
                                                  const unsigned int n_bond_type,
                                                  unsigned int* d_flags)
    {
    // start by identifying which particle we are to handle
    int idx = blockIdx.x * blockDim.x + threadIdx.x;

    if (idx >= N)
        return;

    // load in the length of the list for this thread (MEM TRANSFER: 4 bytes)
    int n_bonds = n_bonds_list[idx];

    // read in the position of our b-particle from the a-b-c triplet. (MEM TRANSFER: 16 bytes)
    Scalar4 postype = __ldg(d_pos + idx);
    Scalar3 pos = make_scalar3(postype.x, postype.y, postype.z);

    Scalar3 sigma_dash_a = d_sigma_dash[idx]; // precomputed
    Scalar sigma_a = d_sigma[idx];            // precomputed

    Scalar4 force = make_scalar4(Scalar(0.0), Scalar(0.0), Scalar(0.0), Scalar(0.0));

    // initialize the virial to 0
    Scalar virial[6];
    for (int i = 0; i < 6; i++)
        virial[i] = Scalar(0.0);

    // loop over all angles
    for (int bond_idx = 0; bond_idx < n_bonds; bond_idx++)
        {
        group_storage<4> cur_bond = blist[blist_idx(idx, bond_idx)];

        int cur_bond_idx = cur_bond.idx[0];
        int cur_tr1_idx = cur_bond.idx[1];
        int cur_tr2_idx = cur_bond.idx[2];
        int cur_bond_type = cur_bond.idx[3];

        if (cur_tr1_idx == cur_tr2_idx)
            continue;

        const group_storage<6>& triangle1 = d_triangles[cur_tr1_idx];

        unsigned int cur_idx_c = d_rtag[triangle1.tag[0]];

        unsigned int iterator = 1;
        while (idx == cur_idx_c || cur_bond_idx == cur_idx_c)
            {
            cur_idx_c = d_rtag[triangle1.tag[iterator]];
            iterator++;
            }

        const group_storage<6>& triangle2 = d_triangles[cur_tr2_idx];

        unsigned int cur_idx_d = d_rtag[triangle2.tag[0]];

        iterator = 1;
        while (idx == cur_idx_d || cur_bond_idx == cur_idx_d)
            {
            cur_idx_d = d_rtag[triangle2.tag[iterator]];
            iterator++;
            }

        // get the b-particle's position (MEM TRANSFER: 16 bytes)
        Scalar4 bb_postype = d_pos[cur_bond_idx];
        Scalar3 bb_pos = make_scalar3(bb_postype.x, bb_postype.y, bb_postype.z);
        // get the c-particle's position (MEM TRANSFER: 16 bytes)
        Scalar4 cc_postype = d_pos[cur_idx_c];
        Scalar3 cc_pos = make_scalar3(cc_postype.x, cc_postype.y, cc_postype.z);
        // get the c-particle's position (MEM TRANSFER: 16 bytes)
        Scalar4 dd_postype = d_pos[cur_idx_d];
        Scalar3 dd_pos = make_scalar3(dd_postype.x, dd_postype.y, dd_postype.z);

        Scalar3 dab = bb_pos - pos;
        Scalar3 dac = cc_pos - pos;
        Scalar3 dad = dd_pos - pos;
        Scalar3 dbc = cc_pos - bb_pos;
        Scalar3 dbd = dd_pos - bb_pos;

        dab = box.minImage(dab);
        dac = box.minImage(dac);
        dad = box.minImage(dad);
        dbc = box.minImage(dbc);
        dbd = box.minImage(dbd);

        // on paper, the formula turns out to be: F = K*\vec{r} * (r_0/r - 1)
        // FLOPS: 14 / MEM TRANSFER: 2 Scalars

        // FLOPS: 42 / MEM TRANSFER: 6 Scalars
        Scalar rsqab = dab.x * dab.x + dab.y * dab.y + dab.z * dab.z;
        Scalar rab = sqrt(rsqab);
        Scalar rsqac = dac.x * dac.x + dac.y * dac.y + dac.z * dac.z;
        Scalar rac = sqrt(rsqac);
        Scalar rsqad = dad.x * dad.x + dad.y * dad.y + dad.z * dad.z;
        Scalar rad = sqrt(rsqad);

        Scalar rsqbc = dbc.x * dbc.x + dbc.y * dbc.y + dbc.z * dbc.z;
        Scalar rbc = sqrt(rsqbc);
        Scalar rsqbd = dbd.x * dbd.x + dbd.y * dbd.y + dbd.z * dbd.z;
        Scalar rbd = sqrt(rsqbd);

        Scalar3 nab, nac, nad, nbc, nbd;
        nab = dab / rab;
        nac = dac / rac;
        nad = dad / rad;
        nbc = dbc / rbc;
        nbd = dbd / rbd;

        Scalar c_accb = nac.x * nbc.x + nac.y * nbc.y + nac.z * nbc.z;

        if (c_accb > 1.0)
            c_accb = 1.0;
        if (c_accb < -1.0)
            c_accb = -1.0;

        Scalar s_accb = sqrt(1.0 - c_accb * c_accb);
        if (s_accb < SMALL)
            s_accb = SMALL;
        s_accb = 1.0 / s_accb;

        Scalar c_addb = nad.x * nbd.x + nad.y * nbd.y + nad.z * nbd.z;

        if (c_addb > 1.0)
            c_addb = 1.0;
        if (c_addb < -1.0)
            c_addb = -1.0;

        Scalar s_addb = sqrt(1.0 - c_addb * c_addb);
        if (s_addb < SMALL)
            s_addb = SMALL;
        s_addb = 1.0 / s_addb;

        Scalar c_abbc = -nab.x * nbc.x - nab.y * nbc.y - nab.z * nbc.z;

        if (c_abbc > 1.0)
            c_abbc = 1.0;
        if (c_abbc < -1.0)
            c_abbc = -1.0;

        Scalar s_abbc = sqrt(1.0 - c_abbc * c_abbc);
        if (s_abbc < SMALL)
            s_abbc = SMALL;
        s_abbc = 1.0 / s_abbc;

        Scalar c_abbd = -nab.x * nbd.x - nab.y * nbd.y - nab.z * nbd.z;

        if (c_abbd > 1.0)
            c_abbd = 1.0;
        if (c_abbd < -1.0)
            c_abbd = -1.0;

        Scalar s_abbd = sqrt(1.0 - c_abbd * c_abbd);
        if (s_abbd < SMALL)
            s_abbd = SMALL;
        s_abbd = 1.0 / s_abbd;

        Scalar c_baac = nab.x * nac.x + nab.y * nac.y + nab.z * nac.z;

        if (c_baac > 1.0)
            c_baac = 1.0;
        if (c_baac < -1.0)
            c_baac = -1.0;

        Scalar s_baac = sqrt(1.0 - c_baac * c_baac);
        if (s_baac < SMALL)
            s_baac = SMALL;
        s_baac = 1.0 / s_baac;

        Scalar c_baad = nab.x * nad.x + nab.y * nad.y + nab.z * nad.z;

        if (c_baad > 1.0)
            c_baad = 1.0;
        if (c_baad < -1.0)
            c_baad = -1.0;

        Scalar s_baad = sqrt(1.0 - c_baad * c_baad);
        if (s_baad < SMALL)
            s_baad = SMALL;
        s_baad = 1.0 / s_baad;

        Scalar cot_accb = c_accb * s_accb;
        Scalar cot_addb = c_addb * s_addb;

        Scalar sigma_hat_ab = (cot_accb + cot_addb) / 2;

        Scalar3 sigma_dash_b = d_sigma_dash[cur_bond_idx]; // precomputed
        Scalar3 sigma_dash_c = d_sigma_dash[cur_idx_c];    // precomputed
        Scalar3 sigma_dash_d = d_sigma_dash[cur_idx_d];    // precomputed

        Scalar sigma_b = d_sigma[cur_bond_idx]; // precomputed
        Scalar sigma_c = d_sigma[cur_idx_c];    // precomputed
        Scalar sigma_d = d_sigma[cur_idx_d];    // precomputed

        Scalar3 dc_abbc, dc_abbd, dc_baac, dc_baad;
        dc_abbc = -nbc / rab - c_abbc / rab * nab;
        dc_abbd = -nbd / rab - c_abbd / rab * nab;
        dc_baac = nac / rab - c_baac / rab * nab;
        dc_baad = nad / rab - c_baad / rab * nab;

        Scalar3 dsigma_hat_ac, dsigma_hat_ad, dsigma_hat_bc, dsigma_hat_bd;
        dsigma_hat_ac = s_abbc * s_abbc * s_abbc * dc_abbc / 2;
        dsigma_hat_ad = s_abbd * s_abbd * s_abbd * dc_abbd / 2;
        dsigma_hat_bc = s_baac * s_baac * s_baac * dc_baac / 2;
        dsigma_hat_bd = s_baad * s_baad * s_baad * dc_baad / 2;

        Scalar3 dsigma_a, dsigma_b, dsigma_c, dsigma_d;
        dsigma_a = (dsigma_hat_ac * rsqac + dsigma_hat_ad * rsqad + 2 * sigma_hat_ab * dab) / 4;
        dsigma_b = (dsigma_hat_bc * rsqbc + dsigma_hat_bd * rsqbd + 2 * sigma_hat_ab * dab) / 4;
        dsigma_c = (dsigma_hat_ac * rsqac + dsigma_hat_bc * rsqbc) / 4;
        dsigma_d = (dsigma_hat_ad * rsqad + dsigma_hat_bd * rsqbd) / 4;

        Scalar dsigma_dash_a = dot(dsigma_hat_ac, dac) + dot(dsigma_hat_ad, dad) + sigma_hat_ab;
        Scalar dsigma_dash_b = dot(dsigma_hat_bc, dbc) + dot(dsigma_hat_bd, dbd) - sigma_hat_ab;
        Scalar dsigma_dash_c = -dot(dsigma_hat_ac, dac) - dot(dsigma_hat_bc, dbc);
        Scalar dsigma_dash_d = -dot(dsigma_hat_ad, dad) - dot(dsigma_hat_bd, dbd);

        Scalar K = __ldg(d_params + cur_bond_type);

        Scalar3 Fa;
        Fa = -K
             * (dsigma_dash_a * sigma_dash_a / sigma_a
                - dot(sigma_dash_a, sigma_dash_a) / (2 * sigma_a * sigma_a) * dsigma_a);
        Fa -= K
              * (dsigma_dash_b * sigma_dash_b / sigma_b
                 - dot(sigma_dash_b, sigma_dash_b) / (2 * sigma_b * sigma_b) * dsigma_b);
        Fa -= K
              * (dsigma_dash_c * sigma_dash_c / sigma_c
                 - dot(sigma_dash_c, sigma_dash_c) / (2 * sigma_c * sigma_c) * dsigma_c);
        Fa -= K
              * (dsigma_dash_d * sigma_dash_d / sigma_d
                 - dot(sigma_dash_d, sigma_dash_d) / (2 * sigma_d * sigma_d) * dsigma_d);

        force.x += Fa.x;
        force.y += Fa.y;
        force.z += Fa.z;
        force.w = K / 2.0 * dot(sigma_dash_a, sigma_dash_a) / sigma_a;

        virial[0] += Scalar(1. / 2.) * dab.x * Fa.x; // xx
        virial[1] += Scalar(1. / 2.) * dab.y * Fa.x; // xy
        virial[2] += Scalar(1. / 2.) * dab.z * Fa.x; // xz
        virial[3] += Scalar(1. / 2.) * dab.y * Fa.y; // yy
        virial[4] += Scalar(1. / 2.) * dab.z * Fa.y; // yz
        virial[5] += Scalar(1. / 2.) * dab.z * Fa.z; // zz
        }

    // now that the force calculation is complete, write out the result (MEM TRANSFER: 20 bytes)
    d_force[idx] = force;

    for (unsigned int i = 0; i < 6; i++)
        d_virial[i * virial_pitch + idx] = virial[i];
    }

/*! \param d_force Device memory to write computed forces
    \param d_virial Device memory to write computed virials
    \param N number of particles
    \param d_pos device array of particle positions
    \param d_rtag device array of particle reverse tags
    \param box Box dimensions (in GPU format) to use for periodic boundary conditions
    \param d_sigma Device memory to write per paricle sigma
    \param d_sigma_dash Device memory to write per particle sigma_dash
    \param blist List of mesh bonds stored on the GPU
    \param d_triangles device array of mesh triangles
    \param n_bonds_list List of numbers of mesh bonds stored on the GPU
    \param d_params K params packed as Scalar variables
    \param n_bond_type number of mesh bond types
    \param block_size Block size to use when performing calculations
    \param d_flags Flag allocated on the device for use in checking for bonds that cannot be
    \param compute_capability Device compute capability (200, 300, 350, ...)

    \returns Any error code resulting from the kernel launch
    \note Always returns hipSuccess in release builds to avoid the hipDeviceSynchronize()
*/
hipError_t gpu_compute_helfrich_force(Scalar4* d_force,
                                      Scalar* d_virial,
                                      const size_t virial_pitch,
                                      const unsigned int N,
                                      const Scalar4* d_pos,
                                      const unsigned int* d_rtag,
                                      const BoxDim& box,
                                      const Scalar* d_sigma,
                                      const Scalar3* d_sigma_dash,
                                      const group_storage<4>* blist,
                                      const group_storage<6>* d_triangles,
                                      const Index2D blist_idx,
                                      const unsigned int* n_bonds_list,
                                      Scalar* d_params,
                                      const unsigned int n_bond_type,
                                      int block_size,
                                      unsigned int* d_flags)
    {
    unsigned int max_block_size;
    hipFuncAttributes attr;
    hipFuncGetAttributes(&attr, (const void*)gpu_compute_helfrich_force_kernel);
    max_block_size = attr.maxThreadsPerBlock;

    unsigned int run_block_size = min(block_size, max_block_size);

    // setup the grid to run the kernel
    dim3 grid(N / run_block_size + 1, 1, 1);
    dim3 threads(run_block_size, 1, 1);

    // run the kernel
    hipLaunchKernelGGL((gpu_compute_helfrich_force_kernel),
                       dim3(grid),
                       dim3(threads),
                       0,
                       0,
                       d_force,
                       d_virial,
                       virial_pitch,
                       N,
                       d_pos,
                       d_rtag,
                       box,
                       d_sigma,
                       d_sigma_dash,
                       blist,
                       d_triangles,
                       blist_idx,
                       n_bonds_list,
                       d_params,
                       n_bond_type,
                       d_flags);

    return hipSuccess;
    }

    } // end namespace kernel
    } // end namespace md
    } // end namespace hoomd