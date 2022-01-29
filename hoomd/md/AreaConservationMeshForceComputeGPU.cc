// Copyright (c) 2009-2021 The Regents of the University of Michigan
// This file is part of the HOOMD-blue project, released under the BSD 3-Clause License.

#include "AreaConservationMeshForceComputeGPU.h"

using namespace std;

/*! \file AreaConservationMeshForceComputeGPU.cc
    \brief Contains code for the AreaConservationhMeshForceComputeGPU class
*/

namespace hoomd
    {
namespace md
    {
/*! \param sysdef System to compute forces on
    \post Memory is allocated, and forces are zeroed.
*/
AreaConservationMeshForceComputeGPU::AreaConservationMeshForceComputeGPU(std::shared_ptr<SystemDefinition> sysdef, std::shared_ptr<MeshDefinition> meshdef)
    : AreaConservationMeshForceCompute(sysdef,meshdef)
    {

    if (!m_exec_conf->isCUDAEnabled())
        {
        m_exec_conf->msg->error()
            << "Creating a AreaConservationMeshForceComputeGPU with no GPU in the execution configuration"
            << endl;
        throw std::runtime_error("Error initializing AreaConservationMeshForceComputeGPU");
        }

    // allocate and zero device memory
    GPUArray<Scalar2> params(this->m_mesh_data->getMeshTriangleData()->getNTypes(),
                                                    this->m_exec_conf);
    m_params.swap(params);

    // allocate flags storage on the GPU
    GPUArray<unsigned int> flags(1, this->m_exec_conf);
    m_flags.swap(flags);

    // reset flags
    ArrayHandle<unsigned int> h_flags(m_flags, access_location::host, access_mode::overwrite);
    h_flags.data[0] = 0;

    unsigned int warp_size = this->m_exec_conf->dev_prop.warpSize;
    m_tuner.reset(
        new Autotuner(warp_size, 1024, warp_size, 5, 100000, "AreaConservation_forces", this->m_exec_conf));
    }

void AreaConservationMeshForceComputeGPU::setParams(unsigned int type, Scalar K, Scalar A0)
    {
    AreaConservationMeshForceCompute::setParams(type, K, A0);

    ArrayHandle<Scalar2> h_params(m_params, access_location::host, access_mode::readwrite);
    // update the local copy of the memory
    h_params.data[type] = make_scalar2(K, A0);
    }

/*! Actually perform the force computation
    \param timestep Current time step
 */
void AreaConservationMeshForceComputeGPU::computeForces(uint64_t timestep)
    {
    // start the profile
    if (this->m_prof)
        this->m_prof->push(this->m_exec_conf, "AreaConservationForce");

    // access the particle data arrays
    ArrayHandle<Scalar4> d_pos(m_pdata->getPositions(), access_location::device, access_mode::read);

    const GPUArray<typename MeshTriangle::members_t>& gpu_meshtriangle_list = this->m_mesh_data->getMeshTriangleData()->getGPUTable();
    const Index2D& gpu_table_indexer = this->m_mesh_data->getMeshTriangleData()->getGPUTableIndexer();

    ArrayHandle<typename MeshTriangle::members_t> d_gpu_meshtrianglelist(gpu_meshtriangle_list,
                                                                         access_location::device,
                                                                         access_mode::read);
    ArrayHandle<unsigned int> d_gpu_n_meshtriangle(this->m_mesh_data->getMeshTriangleData()->getNGroupsArray(),
                                                  access_location::device,
                                                  access_mode::read);                                                                         
    
    BoxDim box = this->m_pdata->getGlobalBox();

    ArrayHandle<Scalar4> d_force(m_force, access_location::device, access_mode::overwrite);
    ArrayHandle<Scalar> d_virial(m_virial, access_location::device, access_mode::overwrite);
    ArrayHandle<Scalar2> d_params(m_params, access_location::device, access_mode::read);

    // access the flags array for overwriting
    ArrayHandle<unsigned int> d_flags(m_flags, access_location::device, access_mode::readwrite);


    m_tuner->begin();
    kernel::gpu_compute_AreaConservation_force(d_force.data,
                                               d_virial.data,
                                               m_virial.getPitch(),
                                               m_pdata->getN(),
                                               d_pos.data,
                                               box,
                                               d_gpu_meshtrianglelist.data,
                                               gpu_table_indexer,
                                               d_gpu_n_meshtriangle.data,
                                               d_params.data,
                                               m_mesh_data->getMeshTriangleData()->getNTypes(),
                                               m_tuner->getParam(),
                                               d_flags.data);

    if (this->m_exec_conf->isCUDAErrorCheckingEnabled())
        {
        CHECK_CUDA_ERROR();

        // check the flags for any errors
        ArrayHandle<unsigned int> h_flags(m_flags, access_location::host, access_mode::read);

        if (h_flags.data[0] & 1)
            {
            this->m_exec_conf->msg->error()
                << "AreaConservation: triangle out of bounds (" << h_flags.data[0]
                << ")" << std::endl
                << std::endl;
            throw std::runtime_error("Error in meshtriangle calculation");
            }
        }
    m_tuner->end();

    if (this->m_prof)
        this->m_prof->pop(this->m_exec_conf);

    }

namespace detail
    {
void export_AreaConservationMeshForceComputeGPU(pybind11::module& m)
    {
    pybind11::class_<AreaConservationMeshForceComputeGPU,
                     AreaConservationMeshForceCompute,
                     std::shared_ptr<AreaConservationMeshForceComputeGPU>>(m, "AreaConservationMeshForceComputeGPU")
        .def(pybind11::init<std::shared_ptr<SystemDefinition>,std::shared_ptr<MeshDefinition>>());
    }

    } // end namespace detail
    } // end namespace md
    } // end namespace hoomd
