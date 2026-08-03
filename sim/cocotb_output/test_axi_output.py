import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

from model import magnitude_log2_q230   # your validated reference, corrected with the /2 fix

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.s_axis_tvalid.value = 0
    dut.m_axis_tready.value = 1
    await Timer(100, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

async def send_sample(dut, re, im):
    """Pack re/im into s_axis_tdata and push through the handshake."""
    word = ((re & 0xFFFF) << 16) | (im & 0xFFFF)
    dut.s_axis_tdata.value = word
    dut.s_axis_tvalid.value = 1
    await RisingEdge(dut.clk)
    while dut.s_axis_tready.value == 0:
        await RisingEdge(dut.clk)
    dut.s_axis_tvalid.value = 0

async def recv_result(dut):
    while True:
        await RisingEdge(dut.clk)
        if dut.m_axis_tvalid.value == 1 and dut.m_axis_tready.value == 1:
            raw = int(dut.m_axis_tdata.value)
            # decode Q6.10 signed
            if raw & 0x8000:
                raw -= 0x10000
            int_part = raw >> 10
            frac_part = raw & 0x3FF
            return int_part + frac_part / 1024.0

@cocotb.test()
async def test_axi_output_random(dut):
    cocotb.start_soon(Clock(dut.clk, 37, units="ns").start())  # 27 MHz
    await reset_dut(dut)

    random.seed(2024)
    max_err = 0.0
    N_TESTS = 200

    for trial in range(N_TESTS):
        re = random.randint(-32768, 32767)
        im = random.randint(-32768, 32767)

        int_part, frac_part, expected = magnitude_log2_q230(re, im)

        cocotb.start_soon(send_sample(dut, re, im))
        actual = await recv_result(dut)

        err = abs(actual - expected)
        max_err = max(max_err, err)

        assert err < 0.05, (
            f"trial {trial}: re={re}, im={im} -> "
            f"expected {expected:.4f}, got {actual:.4f}, err={err:.4f}"
        )

    dut._log.info(f"All {N_TESTS} trials passed. Max error: {max_err:.5f}")