default: sim_silent

.PHONY: build
build: 
	yosys -q -p "synth_ice40 -json build/main.json" $(wildcard *.v)
	nextpnr-ice40 --up5k --package sg48 --pcf pcf/upduino_v3.pcf --top top --json build/main.json --asc build/main.asc
	icepack build/main.asc build/main.bin

.PHONY: build_arachne
build_arachne: 
	yosys -q -p "synth_ice40 -blif build/main.blif" $(wildcard *.v)
	arachne-pnr --device 5k --package sg48 --pcf-file pcf/upduino_v3_arachne.pcf build/main.blif -o build/main.txt
	icepack build/main.txt build/main.bin

.PHONY: flash
flash:
	iceprog -d i:0x0403:0x6014 -k build/main.bin

.PHONY: flash_user
flash_user:
	iceprog -d i:0x0403:0x6014 -k -o 1048576 build/fs.bin

.PHONY: sim
sim:
	verilator -Wall -Wno-fatal -DSIMULATED=1 -DDUMPVARS=1 --trace --binary -j 0 --top top --Mdir sim $(wildcard *.v)
	./sim/Vtop 

.PHONY: sim_silent
sim_silent:
	verilator -Wall -Wno-fatal -DSIMULATED=1 --binary -j 0 --top top --Mdir sim $(wildcard *.v)
	./sim/Vtop 

roms/i8/%.i8: roms/conf/%.txt roms/ch8/%.ch8
	./tools/ice8-tool.py make game ./tools/font.bin $^ $@

build/fs.bin: $(subst .ch8,.i8,$(subst ch8/,i8/,$(wildcard roms/ch8/*.ch8)))
	./tools/ice8-tool.py make fs roms/i8/*.i8 build/fs.bin

.PHONY: filesystem
filesystem: build/fs.bin
