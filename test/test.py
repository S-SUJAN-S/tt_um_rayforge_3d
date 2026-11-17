"""Pin-level smoke tests shared by RTL and Tiny Tapeout gate simulation."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


CLK_PERIOD_NS = 39.72
RGB_MASK = 0x77
HSYNC_MASK = 0x80
VSYNC_MASK = 0x08


async def setup_dut(dut):
    """Drive the default scene and allow synchronized reset release."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)


async def wait_hsync(dut, high):
    for _ in range(801):
        await RisingEdge(dut.clk)
        if bool(int(dut.uo_out.value) & HSYNC_MASK) == high:
            return cocotb.utils.get_sim_time(unit="ns")
    raise AssertionError(f"HSYNC never became {'high' if high else 'low'} in one scanline")


@cocotb.test()
async def test_reset_and_synchronizer(dut):
    await setup_dut(dut)
    assert int(dut.uio_oe.value) == 0xFF
    sync_mask = HSYNC_MASK | VSYNC_MASK
    assert (int(dut.uo_out.value) & sync_mask) == sync_mask


@cocotb.test()
async def test_bist_self_test_pass(dut):
    await setup_dut(dut)
    dut.ui_in.value = 0x80
    await ClockCycles(dut.clk, 1102)
    assert int(dut.uio_out.value) == 0xF3, "Expected PASS and a steady P glyph"


@cocotb.test()
async def test_vga_timing_standards(dut):
    await setup_dut(dut)
    start = await wait_hsync(dut, high=False)
    end = await wait_hsync(dut, high=True)
    expected = 96 * CLK_PERIOD_NS
    assert abs(end - start - expected) < CLK_PERIOD_NS / 2, "HSYNC must span 96 pixel clocks"


@cocotb.test()
async def test_default_active_video(dut):
    await setup_dut(dut)
    active_pixels = 0
    for _ in range(2500):
        await RisingEdge(dut.clk)
        active_pixels += bool(int(dut.uo_out.value) & RGB_MASK)
    assert active_pixels > 500, "Expected nonblack RGB on the first visible lines"
