// tb_ref (Verilator): opl4.v (the wave part of the OPL4) against ymfm::ymf278b (github.com/aaronsgiles/ymfm),
// after sim/opl4 of u16_tsconf_gs_v24. Both get the same writes of a script (gen.py) and the same memory
// (YRW801 + the RAM written by the script); after each sample DO1 and DO2 (L, R) are compared. The FM part
// is not in the RTL here (fm_l / fm_r = 0) and the scripts key no FM channel.
// usage: tb_ref rom.bin script.txt [seed [lat_min lat_max]]
// Prints the first mismatches with the sample number and "samples N reads N errors N".
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "Vopl4.h"
#include "verilated.h"
#include "ymfm_opl.h"

extern int ymfm_interp;   // pcm_interp.py: the interpolation of openMSX in the reference

struct intf : public ymfm::ymfm_interface {
	std::vector<uint8_t> mem;
	intf() : mem(4 << 20, 0) {}
	uint8_t ymfm_external_read(ymfm::access_class, uint32_t a) override { return mem[a & 0x3fffff]; }
	void ymfm_external_write(ymfm::access_class, uint32_t a, uint8_t d) override {
		a &= 0x3fffff;
		if (a >= 0x200000) mem[a] = d;
	}
};

static Vopl4 *top;
static std::vector<uint8_t> rmem(4 << 20, 0);
static uint64_t cycles;
static int lat_cnt = -1;
static unsigned lat_min = 4, lat_max = 40;

static void tick() {
	top->mem_ack = 0;
	if (top->mem_req) {
		if (lat_cnt < 0) lat_cnt = lat_min + rand() % (lat_max - lat_min + 1);
		if (lat_cnt == 0) {
			uint32_t a = top->mem_addr & 0x3fffff;
			if (top->mem_we) {
				if (a >= 0x200000) rmem[a] = top->mem_wdata;
			} else {
				uint32_t w = a & ~1u;
				top->mem_rdata = rmem[w] | (rmem[w + 1] << 8);
			}
			top->mem_ack = 1;
			lat_cnt = -1;
		} else lat_cnt--;
	} else lat_cnt = -1;
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	cycles++;
	top->mem_ack = 0;
	top->wr = 0; top->rd_done = 0; top->sample_tick = 0;
}

static void wait_idle() {
	tick(); tick();
	int guard = 0;
	while (!top->idle) { tick(); if (++guard > 1000000) { fprintf(stderr, "hang\n"); exit(2); } }
}

int main(int argc, char **argv) {
	if (argc < 3) { fprintf(stderr, "usage: tb_ref rom.bin script.txt [seed [lat_min lat_max]]\n"); return 1; }
	unsigned seed = argc > 3 ? atoi(argv[3]) : 1;
	srand(seed);
	if (argc > 5) { lat_min = atoi(argv[4]); lat_max = atoi(argv[5]); }
	intf io;
	FILE *f = fopen(argv[1], "rb");
	if (!f) { perror(argv[1]); return 1; }
	if (fread(io.mem.data(), 1, 0x200000, f) != 0x200000) { fprintf(stderr, "short ROM\n"); return 1; }
	fclose(f);
	memcpy(rmem.data(), io.mem.data(), 0x200000);
	FILE *s = fopen(argv[2], "r");
	if (!s) { perror(argv[2]); return 1; }

	const char *ie = getenv("OPL4_INTERP");
	ymfm_interp = (ie && ie[0] == '1') ? 1 : 0;
	ymfm::ymf278b chip(io);
	chip.reset();

	top = new Vopl4;
	top->fm_l = 0; top->fm_r = 0;
	const char *ri = getenv("OPL4_RTL_INTERP");   // a check of the check: the RTL against the other reference
	top->interp = ri ? (ri[0] == '1') : ymfm_interp;
	top->reset = 1;
	for (int i = 0; i < 4; i++) tick();
	top->reset = 0;
	wait_idle();

	char cmd[16];
	unsigned long nsamp = 0, errors = 0, nreads = 0, shown = 0;
	while (fscanf(s, "%15s", cmd) == 1) {
		if (cmd[0] == '#') {
			char line[256];
			if (fgets(line, sizeof line, s) && shown < 40) printf("#%s", line);   // a marker of the script
			continue;
		}
		if (cmd[0] == 'W') {
			unsigned off, d;
			if (fscanf(s, "%u %x", &off, &d) != 2) break;
			chip.write(off, d);
			top->wr = 1; top->wr_off = off; top->wr_data = d;
			tick();
			wait_idle();
		} else if (cmd[0] == 'R') {
			unsigned off;
			if (fscanf(s, "%u", &off) != 1) break;
			uint8_t ref = chip.read(off);
			top->rd_off = off;
			tick(); tick();
			uint8_t got = top->rd_data;
			top->rd_off = off; top->rd_done = 1;
			tick();
			wait_idle();
			nreads++;
			if (off == 0) { ref &= ~1; got &= ~1; }   // BUSY is not modelled by the reference
			if (ref != got) {
				if (shown < 40) { printf("read %u at sample %lu: ref %02x rtl %02x\n", off, nsamp, ref, got); shown++; }
				errors++;
			}
		} else if (cmd[0] == 'S') {
			unsigned n;
			if (fscanf(s, "%u", &n) != 1) break;
			for (unsigned i = 0; i < n; i++) {
				ymfm::ymf278b::output_data out;
				chip.generate(&out, 1);
				top->sample_tick = 1;
				tick();
				wait_idle();
				int r[4] = { (int16_t)top->do1_l, (int16_t)top->do1_r, (int16_t)top->do2_l, (int16_t)top->do2_r };
				int e[4] = { out.data[2], out.data[3], out.data[4], out.data[5] };
				if (memcmp(r, e, sizeof r)) {
					if (shown < 40) {
						printf("sample %lu: ref %d %d %d %d  rtl %d %d %d %d\n", nsamp, e[0], e[1], e[2], e[3], r[0], r[1], r[2], r[3]);
						shown++;
					}
					errors++;
				}
				nsamp++;
			}
		}
	}
	printf("samples %lu reads %lu errors %lu\n", nsamp, nreads, errors);
	delete top;
	return errors ? 1 : 0;
}
