// Copyright (c) 2018-2020, Michael P. Howard
// Copyright (c) 2021-2022, Auburn University

// Maintainer: astatt

/*!
 * \file CosineChannelFiller.h
 * \brief Definition of virtual particle filler for mpcd::detail::CosineChannel.
 */

#ifndef MPCD_COSINE_CHANNEL_FILLER_H_
#define MPCD_COSINE_CHANNEL_FILLER_H_

#ifdef __HIPCC__
#error This header cannot be compiled by nvcc
#endif

#include "CosineChannelGeometry.h"
#include "VirtualParticleFiller.h"
#include "SystemDefinition.h"
#include "/pybind11/pybind11.h"

namespace hoomd
{
namespace mpcd
{

//! Adds virtual particles to the MPCD particle data for SinusoidalChannel
/*!
 * Particles are added to the volume that is overlapped by any of the cells that are also "inside" the channel,
 * subject to the grid shift.
 */
class PYBIND11_EXPORT CosineChannelFiller : public mpcd::ManualVirtualParticleFiller
    {
    public:
        CosineChannelFiller(std::shared_ptr<mpcd::SystemDefinition> sysdef,
                                Scalar density,
                                unsigned int type,
                                std::shared_ptr<::Variant> T,
                                unsigned int seed,
                                std::shared_ptr<const mpcd::CosineChannel> geom);

        virtual ~CosineChannelFiller();

        void setGeometry(std::shared_ptr<const mpcd::CosineChannelGeometry> geom)
            {
            m_geom = geom;
            }

    protected:
        std::shared_ptr<const detail::CosineChannel> m_geom;
        Scalar m_thickness;       //!< thickness of virtual particle buffer zone
        Scalar m_Amplitude;       //!< amplitude of  channel wall cosine: 0.5(H_wide - H_narrow)
        Scalar m_pi_period_div_L; //!< period of channel wall cosine: 2*pi*period/Lx
        Scalar m_H_narrow;        //!< half width of the narrowest height of the channel

        //! Compute the total number of particles to fill
        virtual void computeNumFill();

        //! Draw particles within the fill volume
        virtual void drawParticles(unsigned int timestep);
    };

namespace detail
{
//! Export CosineChannelFiller to python
void export_CosineChannelFiller(pybind11::module& m);
} // end namespace detail
} // end namespace mpcd
} // end namespace hoomd

#endif // MPCD_COSINE_CHANNEL_FILLER_H_
