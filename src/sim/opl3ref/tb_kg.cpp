// tb_kg (Verilator): opl4_kg as in the core (CLK 84 MHz, CLK28 = CLK / 3), an FM instrument written through the
// ports #C4..#C7 (bank 0 address / data, bank 1 address / data), OUT_L taken at each new sample (SAMPLE_T).
// The FM path into the 44.1 kHz output: the FM samples (49.5 kHz) taken with or without the interpolation.
// usage: tb_kg patches.txt interp first count
//   plays the patches first .. first + count - 1 on channel 0 at two notes (block 4 / 6), 3000 samples each,
//   and writes dump/kg_pNN_nK_iI.raw (int16 OUT_L at 44.1 kHz).
#include <cstdio>
#include <cstdlib>
#include "Vopl4_kg.h"
#include "verilated.h"

static Vopl4_kg *top;
static unsigned long half;
static void unit() {            // half a period of CLK; CLK28 toggles every 3 of them
	top->CLK = !top->CLK;
	if (half % 3 == 0) top->CLK28 = !top->CLK28;
	half++;
	if (top->MEM_REQ && top->CLK) { top->MEM_ACK = 1; top->MEM_RDATA = 0; }
	top->eval();
	if (top->CLK) top->MEM_ACK = 0;
}
static void clk(int n) { for (int i = 0; i < 2 * n; i++) unit(); }

static void out(int port, int data) {
	top->A = port; top->DI = data; top->IORQ_n = 0; top->WR_n = 0;
	clk(30);
	top->IORQ_n = 1; top->WR_n = 1;
	clk(1000);
}
static void fm(int bank, int reg, int data) {
	out(bank ? 0xc6 : 0xc4, reg);
	out(bank ? 0xc7 : 0xc5, data);
}

int main(int argc, char **argv) {
	if (argc < 5) { fprintf(stderr, "usage: tb_kg patches.txt interp first count\n"); return 1; }
	FILE *f = fopen(argv[1], "r");
	if (!f) { perror(argv[1]); return 1; }
	int interp = atoi(argv[2]), first = atoi(argv[3]), count = atoi(argv[4]);
	top = new Vopl4_kg;
	top->IORQ_n = 1; top->WR_n = 1; top->RD_n = 1; top->M1_n = 1; top->DOS = 0;
	top->INTERP = interp;
	top->RESET = 1; clk(100);
	top->RESET = 0; clk(20000);
	fm(1, 0x05, 0x03);              // NEW, NEW2
	static const int notes[2][2] = { {4, 0x244}, {6, 0x16b} };
	unsigned p[11];
	for (int np = 0; fscanf(f, "%x %x %x %x %x %x %x %x %x %x %x", &p[0], &p[1], &p[2], &p[3], &p[4], &p[5], &p[6],
	                        &p[7], &p[8], &p[9], &p[10]) == 11; np++) {
		if (np < first) continue;
		if (np >= first + count) break;
		static const int regs[10] = { 0x20, 0x23, 0x40, 0x43, 0x60, 0x63, 0x80, 0x83, 0xe0, 0xe3 };
		for (int i = 0; i < 10; i++) fm(0, regs[i], p[i]);
		fm(0, 0xc0, (p[10] & 0x0f) | 0x30);
		for (int k = 0; k < 2; k++) {
			fm(0, 0xa0, notes[k][1] & 0xff);
			fm(0, 0xb0, 0x20 | (notes[k][0] << 2) | (notes[k][1] >> 8));
			char fn[64]; snprintf(fn, sizeof fn, "dump/kg_p%02d_n%d_i%d.raw", np, k + 1, interp);
			FILE *o = fopen(fn, "wb");
			int t = top->SAMPLE_T;
			for (int n = 0; n < 3000; ) {
				clk(1);
				if (top->SAMPLE_T != t) {
					t = top->SAMPLE_T;
					int16_t v = top->OUT_L;
					fwrite(&v, 2, 1, o);
					n++;
				}
			}
			fclose(o);
			fm(0, 0xb0, (notes[k][0] << 2) | (notes[k][1] >> 8));
			clk(84000 * 20);   // 20 ms of release
		}
		printf("patch %d done\n", np);
	}
	delete top;
	return 0;
}
