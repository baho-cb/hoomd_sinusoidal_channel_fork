// Copyright (c) 2018-2020, Michael P. Howard
// Copyright (c) 2021-2022, Auburn University


/*!
 * \file CosineExpansionContractionFillerGPU.h
 * \brief Definition of virtual particle filler for mpcd::detail::CosineExpansionContraction on the GPU.
 */

#ifndef MPCD_COSINE_EXPANSION_CONSTRICTION_FILLER_GPU_H_
#define MPCD_COSINE_EXPANSION_CONSTRICTION_FILLER_GPU_H_

#ifdef __HIPCC__
#error This header cannot be compiled by nvcc
#endif

#include "CosineExpansionContractionFiller.h"
#include "hoomd/Autotuner.h"
#include <pybind11/pybind11.h>

namespace hoomd
{
namespace mpcd
{

//! Adds virtual particles to the MPCD particle data for SinusoidalExpansionConstriction using the GPU
class PYBIND11_EXPORT CosineExpansionContractionFillerGPU : public CosineExpansionContractionFiller
    {
    public:
        //! Constructor
        CosineExpansionContractionFillerGPU(std::shared_ptr<mpcd::SystemDefinition> sysdef,
                                                 Scalar density,
                                                 unsigned int type,
                                                 std::shared_ptr<::Variant> T,
                                                 unsigned int seed,
                                                 std::shared_ptr<const detail::CosineExpansionContraction> geom);

        //! Set autotuner parameters
        /*!
         * \param enable Enable/disable autotuning
         * \param period period (approximate) in time steps when returning occurs
         */
        virtual void setAutotunerParams(bool enable, unsigned int period)
            {
            SinusoidalExpansionConstrictionFiller::setAutotunerParams(enable, period);

            m_tuner->setEnabled(enable); m_tuner->setPeriod(period);
            }

    protected:
        //! Draw particles within the fill volume on the GPU
        virtual void drawParticles(unsigned int timestep);

    private:
        std::unique_ptr<::Autotuner> m_tuner;   //!< Autotuner for drawing particles
    };

namespace detail
{
//! Export SinusoidalExpansionConstrictionFillerGPU to python
void export_CosineExpansionContractionFillerGPU(pybind11::module& m);
} // end namespace detail
} // end namespace mpcd
} // end namespace hoomd
#endif // MPCD_COSINE_EXPANSION_CONTRACTION_FILLER_GPU_H_
