// Copyright (c) 2009-2022 The Regents of the University of Michigan.
// Part of HOOMD-blue, released under the BSD 3-Clause License.

#include "AnisoPotentialPairGPU.h"
#include "EvaluatorPairLJ.h"
#include "EvaluatorPairYukawa.h"
#include "SingleEnvelope.h"
#include "PairModulator.h"

namespace hoomd
    {
namespace md
    {
namespace detail
    {
void export_AnisoPotentialPairJanusSingleLJGPU(pybind11::module& m)
    {
        export_AnisoPotentialPairGPU<PairModulator<EvaluatorPairLJ, SingleEnvelope>>(
        m,
        "AnisoPotentialPairJanusSingleLJGPU");
    }
void export_AnisoPotentialPairJanusSingleYukawaGPU(pybind11::module& m) {
    export_AnisoPotentialPairGPU<PairModulator<EvaluatorPairYukawa, SingleEnvelope>>(
        m,
        "AnisoPotentialPairJanusSingleYukawaGPU");
}
   
    } // end namespace detail
    } // end namespace md
    } // end namespace hoomd
