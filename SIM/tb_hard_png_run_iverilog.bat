del sim.out dump.vcd
iverilog  -g2005-sv  -o sim.out  tb_hard_png.sv  ../RTL/hard_png.sv  ../RTL/huffman_builder.sv  ../RTL/huffman_decoder.sv
vvp -n sim.out
del sim.out
pause