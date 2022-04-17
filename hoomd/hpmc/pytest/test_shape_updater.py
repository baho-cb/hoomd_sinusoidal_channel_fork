# Copyright (c) 2009-2022 The Regents of the University of Michigan.
# Part of HOOMD-blue, released under the BSD 3-Clause License.

import hoomd
from hoomd import hpmc
import numpy as np
import pytest
from hoomd.hpmc.update import Shape
from hoomd.hpmc.shape_move import ShapeMove, Vertex, ShapeSpace, Elastic

shape_move_classes = [Vertex, ShapeSpace, Elastic]


def _test_callback(typeid, param_list):
    pass

shape_move_constructor_args = [
    (Vertex, dict(move_probability=0.7)),
    (ShapeSpace, dict(callback=_test_callback, move_probability=1)),
    (Elastic, dict(stiffness=hoomd.variant.Constant(10), move_probability=0.5)),
]

shape_move_valid_attrs = [
    (Vertex(), "move_probability", 0.1),
    (ShapeSpace(callback=_test_callback), "move_probability", 0.1),
    (ShapeSpace(callback=_test_callback), "callback", lambda type, param_list: {}),
    (Elastic(1), "move_probability", 0.5),
    (Elastic(1), "stiffness", hoomd.variant.Constant(10)),
    (Elastic(1), "stiffness", hoomd.variant.Ramp(1, 5, 0, 100)),
    (Elastic(1), "stiffness", hoomd.variant.Cycle(1, 5, 0, 10, 20, 10, 15)),
    (Elastic(1), "stiffness", hoomd.variant.Power(1, 5, 3, 0, 100))
]

shape_updater_valid_attrs = [("trigger", hoomd.trigger.Periodic(10)),
                             ("trigger", hoomd.trigger.After(100)),
                             ("trigger", hoomd.trigger.Before(100)),
                             ("type_select", 2), ("nweeps", 4),
                             ("shape_move", Vertex()),
                             ("shape_move", ShapeSpace(callback=_test_callback)),
                             ("shape_move", Elastic(stiffness=10))]

updater_constructor_args = [
    dict(trigger=hoomd.trigger.Periodic(10),
         shape_move=ShapeMove(move_probability=1)),
    dict(trigger=hoomd.trigger.After(100),
         shape_move=Vertex(),
         type_select=4,
         nsweeps=2),
    dict(trigger=hoomd.trigger.Before(100),
         shape_move=ShapeSpace(callback=_test_callback),
         nsweeps=4),
    dict(trigger=hoomd.trigger.Periodic(1000),
         shape_move=ShapeSpace(callback=_test_callback),
         type_select=1),
    dict(trigger=hoomd.trigger.Periodic(10),
         shape_move=Elastic(stiffness=10),
         type_select=3,
         pretend=True)
]

type_parameters = [
    (ShapeSpace(callback=_test_callback), "params", [0.1, 0.3, 0.4]),
    (Vertex(), "volume", 1.2),
    # (Elastic(), "reference_shape", {"diameter": 1}),
    (Shape(trigger=1, shape_move=Vertex()), "step_size", 0.4)
]


@pytest.mark.parametrize("shape_move_class,params",
                         shape_move_constructor_args)
def test_valid_construction_shape_moves(shape_move_class,params):

    move = shape_move_class(**params)

    # validate the params were set properly
    for attr, value in params.items():
        assert getattr(move, attr) == value


@pytest.mark.parametrize("updater_constructor_args", updater_constructor_args)
def test_valid_construction_shape_updater(updater_constructor_args):

    updater = hpmc.update.Shape(**updater_constructor_args)

    # validate the params were set properly
    for attr, value in updater_constructor_args.items():
        assert getattr(updater, attr) == value


@pytest.mark.parametrize("shape_move_obj,attr,value", shape_move_valid_attrs)
def test_valid_setattr_shape_move(shape_move_obj, attr, value):
    """Test that the shape move classes can get and set attributes."""

    setattr(shape_move_obj, attr, value)
    assert getattr(shape_move_obj, attr) == value


@pytest.mark.parametrize("attr,value", shape_updater_valid_attrs)
def test_valid_setattr_shape_updater(attr, value):
    """Test that the Shape updater can get and set attributes."""
    updater = hpmc.update.Shape(trigger=1,
                                shape_move=ShapeMove(move_probability=1))

    setattr(updater, attr, value)
    assert getattr(updater, attr) == value


@pytest.mark.parametrize("obj,attr,value", type_parameters)
def test_type_parameters(obj, attr, value):
    getattr(obj, attr)["A"] = value
    assert getattr(obj, attr)["A"] == value


def test_vertex_shape_move(device, simulation_factory,
                           two_particle_snapshot_factory):

    verts = np.asarray([[-1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, -1, -1],
                        [-1, 1, 1], [1, -1, 1], [1, 1, -1], [1, 1, 1]]) / 2

    move = Vertex()
    move.volume["A"] = 1

    updater = hpmc.update.Shape(trigger=1, shape_move=move, step_size=0.2, nsweeps=2)
    updater.shape_move = move

    mc = hoomd.hpmc.integrate.ConvexPolyhedron()
    mc.d["A"] = 0
    mc.a["A"] = 0
    mc.shape["A"] = dict(vertices=verts)

    # create simulation & attach objects
    sim = simulation_factory(two_particle_snapshot_factory(d=10))
    sim.operations.integrator = mc
    sim.operations += updater

    # test attachmet before first run
    assert not move._attached
    assert not updater._attached

    sim.run(0)

    # test attachmet after first run
    assert move._attached
    assert updater._attached

    # run with 0 probability of performing a move:
    #  - shape should remain unchanged
    #  - all moves accepted
    move.move_probability = 0
    sim.run(20)
    assert np.allclose(mc.shape["A"]["vertices"], verts)
    assert updater.shape_moves[0] == 40
    assert updater.shape_moves[1] == 0

    # always attempt a shape move:
    #  - shape should change, some attemps are accepted but
    #  - volume should remain unchanged
    move.move_probability = 1
    sim.run(20)
    assert updater.shape_moves[0] != 0
    assert np.sum(updater.shape_moves) == 40
    assert not np.allclose(mc.shape["A"]["vertices"], verts)
    assert np.isclose(updater.total_particle_volume, 2)


def test_python_callback_shape_move(device, simulation_factory,
                                    two_particle_snapshot_factory):
    """Test ShapeSpace with a toy class that randomly squashes spheres \
           into oblate ellipsoids with constant volume."""

    class ScaleEllipsoid:

        def __init__(self, a, b, c):
            self.vol_factor = 4 * np.pi / 3
            self.volume = self.vol_factor * a * b * c
            self.default_dict = dict(ignore_statistics=True)

        def __call__(self, type_id, param_list):
            x = param_list[0]
            b = (self.volume / x / (self.vol_factor))**(1 / 3)
            ret = dict(a=x * b, b=b, c=b, **self.default_dict)
            return ret

    ellipsoid = dict(a=1, b=1, c=1)

    move = ShapeSpace(callback=ScaleEllipsoid(**ellipsoid))
    move.params["A"] = [1]

    updater = hpmc.update.Shape(trigger=1, shape_move=move, step_size=0.2, nsweeps=2)
    updater.shape_move = move

    mc = hoomd.hpmc.integrate.Ellipsoid()
    mc.d["A"] = 0
    mc.a["A"] = 0
    mc.shape["A"] = ellipsoid

    # create simulation & attach objects
    sim = simulation_factory(two_particle_snapshot_factory(d=10))
    sim.operations.integrator = mc
    sim.operations += updater

    # test attachmet before first run
    assert not move._attached
    assert not updater._attached

    sim.run(0)

    # test attachmet after first run
    assert move._attached
    assert updater._attached

    # run with 0 probability of performing a move:
    #  - shape and params should remain unchanged
    #  - all moves accepted
    move.move_probability = 0
    sim.run(20)
    assert updater.shape_moves[0] == 40
    assert updater.shape_moves[1] == 0
    assert np.allclose(mc.shape["A"]["a"], ellipsoid["a"])
    assert np.allclose(mc.shape["A"]["b"], ellipsoid["b"])
    assert np.allclose(mc.shape["A"]["c"], ellipsoid["c"])
    assert np.allclose(move.params["A"], [1])

    # always attempt a shape move:
    #  - shape and params should change
    #  - only some moves are accepted
    #  - volume should remain unchanged
    move.move_probability = 1
    sim.run(20)
    assert updater.shape_moves[0] != 0
    assert updater.shape_moves[1] != 0
    assert np.sum(updater.shape_moves) == 40
    assert not np.allclose(mc.shape["A"]["a"], ellipsoid["a"])
    assert not np.allclose(mc.shape["A"]["b"], ellipsoid["b"])
    assert not np.allclose(mc.shape["A"]["c"], ellipsoid["c"])
    assert not np.allclose(move.params["A"], [1])
    assert np.allclose(updater.total_particle_volume, 2 * 4 * np.pi / 3)


def test_elastic_shape_move(device, simulation_factory,
                            two_particle_snapshot_factory):
    # test pending a solutioon th the typeparam
    # validation for the reference_shape
    pass
