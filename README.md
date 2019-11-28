# CNN accelerator 

training은 하지 않고 Inference만 하는 acclerator를 만들어 FPGA board에 올린다.
Conv layer, FC layer, Pooling layer를 reconfigurable하게 구현한다.

## FC layer module

submodule로 control, MAC(8-bit 2's complement), AXI-stream을 사용한다.

port는 control용 APB signal과 data용 AXI-stream이 있다.

fc module 안에 BRAM과 MAC연산기를 적절히 배치하여 설계한다.
BRAM의 경우 input, weight, bias를 쓰기 시작하는 address를 잘 정해주어야 한다.
