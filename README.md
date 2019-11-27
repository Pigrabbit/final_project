# CNN accelerator 

training은 하지 않고 Inference만 하는 acclerator를 만들어 FPGA board에 올린다.
Conv layer, FC layer, Pooling layer를 reconfigurable하게 구현한다.

## FC layer module

submodule로 control, MAC(8-bit 2's complement), AXI-stream을 사용한다.

port는 control용 APB signal과 data용 AXI-stream이 있다.

