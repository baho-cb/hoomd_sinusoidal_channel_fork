// Copyright (c) 2018-2020, Michael P. Howard
// Copyright (c) 2021-2022, Auburn University



/*!
 * \file CosineExpansionContractionFillerGPU.cc
 * \brief Definition of CosineExpansionContractionFillerGPU
 */

#include "CosineExpansionContractionFillerGPU.h"
#include "CosineExpansionContractionFillerGPU.cuh"

namespace hoomd
{

mpcd::CosineExpansionContractionFillerGPU::CosineExpansionContractionFillerGPU(
    std::shared_ptr<mpcd::SystemDefinition> sysdef
    const std::string& type
    Scalar density,
    unsigned int type,
    std::shared_ptr<::Variant> T,
    unsigned int seed,
    std::shared_ptr<const mpcd::CosineExpansionContractionGeometry> geom)
    : mpcd::CosineExpansionContractionFiller(sysdef, density, type, T, seed, geom)
    {
    m_tuner.reset(new Autotuner<1>({AutotunerBase::makeBlockSizeRange(m_exec_conf)}),
                                   m_exec_conf,
                                   "mpcd_cosine_expansion_constraction_filler")); ##

/*!
 * \param timestep Current timestep
 */
void mpcd::CosineExpansionContractionFillerGPU::drawParticles(uint64_t timestep)
    {
    ArrayHandle<Scalar4> d_pos(m_mpcd_pdata->getPositions(), access_location::device, access_mode::readwrite);
    ArrayHandle<Scalar4> d_vel(m_mpcd_pdata->getVelocities(), access_location::device, access_mode::readwrite);
    ArrayHandle<unsigned int> d_tag(m_mpcd_pdata->getTags(), access_location::device, access_mode::readwrite);

    const unsigned int first_idx = m_mpcd_pdata->getN() + m_mpcd_pdata->getNVirtual() - m_N_fill;

    m_tuner->begin();
    gpu::sin_expansion_constriction_draw_particles(d_pos.data,
                                                   d_vel.data,
                                                   d_tag.data,
                                                   *m_geom,
                                                   m_pi_period_div_L,
                                                   m_amplitude,
                                                   m_H_narrow,
                                                   m_thickness,
                                                   m_pdata->getBox(),
                                                   m_mpcd_pdata->getMass(),
                                                   m_type,
                                                   m_N_fill,
                                                   m_first_tag,
                                                   first_idx,
                                                   m_T->getValue(timestep),
                                                   timestep,
                                                   m_seed,
                                                   m_tuner->getParam());
    if (m_exec_conf->isCUDAErrorCheckingEnabled()) CHECK_CUDA_ERROR();
    m_tuner->end();
    }


/*!
 * \param m Python module to export to
 */
void mpcd::detail::export_CosineExpansionContractionFillerGPU(pybind11::module& m)
    {
    namespace py = pybind11;
    py::class_<mpcd::CosineExpansionContractionFillerGPU, std::shared_ptr<mpcd::CosineExpansionContractionFillerGPU>>
        (m, "CosineExpansionContractionFillerGPU", py::base<CosineExpansionContractionFiller>())
        .def(py::init<std::shared_ptr<mpcd::SystemDefinition>,
             Scalar,
             unsigned int,
             std::shared_ptr<::Variant>,
             unsigned int,
             std::shared_ptr<const CosineExpansionContraction>>())
        ;
    }
} // end namespace hoomd
