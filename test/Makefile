# =============================================================================
# Makefile for Cocotb Verification: RayForge-X
# =============================================================================

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += ../src/vga_timing_gen.v
VERILOG_SOURCES += ../src/perspective_ground.v
VERILOG_SOURCES += ../src/sdf_engine.v
VERILOG_SOURCES += ../src/sphere_tracer_pipeline.v
VERILOG_SOURCES += ../src/phong_shading.v
VERILOG_SOURCES += ../src/bist_diagnostic.v
VERILOG_SOURCES += ../src/tt_um_rayforge_3d.v

TOPLEVEL = tt_um_rayforge_3d
MODULE = test

include $(shell cocotb-config --makefiles)/Makefile.sim
