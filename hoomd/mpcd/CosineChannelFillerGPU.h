// Copyright (c) 2018-2020, Michael P. Howard
// Copyright (c) 2021-2022, Auburn University
// This file is part of the azplugins project, released under the Modified BSD License.

// Maintainer: astatt


/*!
 * \file CosineChannelFillerGPU.h
 * \brief Definition of virtual particle filler for mpcd::CosineChannelGeometry on the GPU.
 */

#ifndef MPCD_COSINE_CHANNEL_FILLER_GPU_H_
#define MPCD_COSINE_CHANNEL_FILLER_GPU_H_

#ifdef __HIPCC__
#error This header cannot be compiled by nvcc
#endif

#include "CosineChannelFiller.h"
#include "hoomd/Autotuner.h"
#include "pybind11/pybind11.h"

namespace hoomd
{
namespace mpcd
{

//! Adds virtual particles to the MPCD particle data for SinusoidalExpansionConstriction using the GPU
class PYBIND11_EXPORT CosineChannelFillerGPU : public CosineChannelFiller
    {
    public:
        //! Constructor
        CosineChannelFillerGPU(std::shared_ptr<mpcd::SystemDefinition> sysdef,
                                   Scalar density,
                                   unsigned int type,
                                   std::shared_ptr<::Variant> T,
                                   unsigned int seed,
                                   std::shared_ptr<const detail::CosineChannel> geom);

        //! Set autotuner parameters
        /*!
         * \param enable Enable/disable autotuning
         * \param period period (approximate) in time steps when returning occurs
         */
        virtual void setAutotunerParams(bool enable, unsigned int period)
            {
            CosineChannelFiller::setAutotunerParams(enable, period);

            m_tuner->setEnabled(enable); m_tuner->setPeriod(period);
            }

    protected:
        //! Draw particles within the fill volume on the GPU
        virtual void drawParticles(uint64_t timestep);

    private:
        std::unique_ptr<::Autotuner> m_tuner;   //!< Autotuner for drawing particles
    };

namespace detail
{
//! Export CosineChannelFillerGPU to python
void export_CosineChannelFillerGPU(pybind11::module& m);
} // end namespace detail
} // end namespace mpcd
} //end namespace hoomd
#endif // MPCD_COSINE_CHANNEL_FILLER_GPU_H_
