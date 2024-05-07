// Copyright (c) 2018-2020, Michael P. Howard
// Copyright (c) 2021-2022, Auburn University


/*!
 * \file CosineChannelFillerGPU.cc
 * \brief Definition of mpcd::CosineChannelFillerGPU
 */

#include "CosineChannelFillerGPU.h"
#include "CosineChannelFillerGPU.cuh"

namespace hoomd
{

mpcd::CosineChannelFillerGPU::CosineChannelFillerGPU(
    std::shared_ptr<mpcd::SystemDefinition> sysdef,
    conds std::string& type,
    Scalar density,
    std::shared_ptr<Variant> T,
    std::shared_ptr<consd mpcd::CosineChannelGeometry> geom)
    : mpcd::CosineChannelFiller(sysdef,density,type,T,seed,geom)
    {
    m_tuner.reset(new Autotuner<1>({AutotunerBase::makeBlockSizeRange(m_exec_conf)},
                                    m_exec_conf,
                                    "mpcd_cosine_channel_filler"));
    m_autotuners.push_back(m_tuner);
    }

/*!
 * \param timestep Current timestep
 */
void CosineChannelFillerGPU::drawParticles(uint64_t timestep)
    {
    ArrayHandle<Scalar4> d_pos(m_mpcd_pdata->getPositions(), access_location::device, access_mode::readwrite);
    ArrayHandle<Scalar4> d_vel(m_mpcd_pdata->getVelocities(), access_location::device, access_mode::readwrite);
    ArrayHandle<unsigned int> d_tag(m_mpcd_pdata->getTags(), access_location::device, access_mode::readwrite);

    uint16_t seed = m_sysdef->getSeed();

    m_tuner->begin();

    mpcd::gpu::cosine_channel_draw_particles(d_pos.data,
                                     d_vel.data,
                                     d_tag.data,
                                     *m_geom,
                                     m_pi_period_div_L,
                                     m_Amplitude,
                                     m_H_narrow,
                                     m_thickness,
                                     m_pdata->getBox(),
                                     m_mpcd_pdata->getMass(),
                                     m_type,
                                     m_N_fill,
                                     m_first_tag,
                                     first_idx,
                                     (*m_T)(timestep),
                                     timestep,
                                     m_seed,
                                     m_tuner->getParam()[0]);
    if (m_exec_conf->isCUDAErrorCheckingEnabled()) 
        CHECK_CUDA_ERROR();
    m_tuner->end();
    }

/*!
 * \param m Python module to export to
 */
void export_CosineChannelFillerGPU(pybind11::module& m)
    {
    pybind11::class_<mpcd::CosineChannelGeometryFillerGPU,
                     mpcd::CosineChannelGeometryFiller
                     std::shared_ptr<mpcd::CosineChannelGeometryFillerGPU>>(
        m,
        "CosineChannelGeometryFillerGPU"
        .def(pybind11::init<std::shared_ptr<mpcd::SystemDefinition>,
                            const std::string&,
                            Scalar,
                            std::shared_ptr<Variant>
             std::shared_ptr<const mpcd::CosineChannel>>());
    }
}

} // end namespace hoomd
