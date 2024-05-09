// Copyright (c) 2018-2020, Michael P. Howard
// Copyright (c) 2021-2022, Auburn University


/*!
 * \file CosineExpansionContractionFiller.h
 * \brief Definition of virtual particle filler for mpcd::CosineExpansionContraction.
 */

#ifndef MPCD_COSINE_EXPANSION_CONSTRICTION_FILLER_H_
#define MPCD_COSINE_EXPANSION_CONSTRICTION_FILLER_H_

#ifdef __HIPPC__
#error This header cannot be compiled by nvcc
#endif

#include "CosineExpansionContractionGeometry.h"
#include "hoomd/mpcd/VirtualParticleFiller.h"
#include "hoomd/mpcd/SystemDefinition.h"

#include <pybind11/pybind11.h>

namespace hoomd
{
namespace mpcd
//! Adds virtual particles to the MPCD particle data for CosineExpansionContraction
/*!
 * Particles are added to the volume that is overlapped by any of the cells that are also "inside" the channel,
 * subject to the grid shift.
 */
class PYBIND11_EXPORT CosineExpansionContractionFiller : public mpcd::VirtualParticleFiller
    {
    public:
    CosineExpansionContractionFiller(std::shared_ptr<mpcd::SystemDefinition> sysdef,
                                     Scalar density,
                                     unsigned int type,
                                     std::shared_ptr<::Variant> T,
                                     unsigned int seed,
                                     std::shared_ptr<const detail::CosineExpansionContraction> geom);

    virtual ~CosineExpansionContractionFiller();

    std::shared_ptr<const mpcd::CosineExpansionContraction> getGeometry() const
            {
            return m_geom;
            }

    void setGeometry(std::shared_ptr<const detail::CosineExpansionContraction> geom)
        {
        m_geom = geom;
        }

    protected:
    std::shared_ptr<const detail::CosineExpansionContraction> m_geom;
    Scalar m_thickness;       //!< thickness of virtual particle buffer zone
    Scalar m_amplitude;       //!< amplitude of  channel wall cosine: 0.5(H_wide - H_narrow)
    Scalar m_pi_period_div_L; //!< period of channel wall cosine: 2*pi*period/Lx
    Scalar m_H_narrow;        //!< half width of the narrowest height of the channel

    //! Compute the total number of particles to fill
    virtual void computeNumFill();

    //! Draw particles within the fill volume
    virtual void drawParticles(unsigned int timestep);
    };

namespace detail
{
//! Export CosineExpansionContractionFiller to python
void export_CosineExpansionContractionFiller(pybind11::module& m);
} // end namespace detail
} // end namespace mpcd
} // end namespace hoomd

#endif // MPCD_COSINE_EXPANSION_CONSTRICTION_FILLER_H_
