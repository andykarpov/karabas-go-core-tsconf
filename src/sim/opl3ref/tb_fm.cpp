// tb_fm (Verilator): the FM part of the OPL4 (opl3_fm, opl3_fpga) against ymfm::ymf262. Both get the same
// register writes; after each sample tick out_l / out_r of the RTL (x 2: ymfm has 14-bit operators, opl3_fpga
// 13-bit, as opl4.v scales them) are compared with the outputs A / B of ymfm.
// usage: tb_fm patches.txt
//   patches.txt: lines of 11 hex bytes, an OPL instrument of MoonBlaster 1.4 (MSX-AUDIO): mod 20, car 20,
//   mod 40, car 40, mod 60, car 60, mod 80, car 80, mod E0, car E0, C0 (FB / CON).
// Each patch is played on channel 0 at three notes (key on 3000 samples, key off 1000). Prints per note the
// RMS of the reference, the RMS of the difference, the largest difference and the samples not equal.
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include "Vopl3_fm.h"
#include "verilated.h"
#include "ymfm_opl.h"

struct intf : public ymfm::ymfm_interface {};

static Vopl3_fm *top;
static void clk(int n) {
	for (int i = 0; i < n; i++) {
		top->clk = 0; top->eval();
		top->clk = 1; top->eval();
	}
}

static ymfm::ymf262 *chip;
static void wr(int bank, int reg, int data) {
	chip->write(bank ? 2 : 0, reg);
	chip->write(bank ? 3 : 1, data);
	top->wr_word = (bank << 16) | (reg << 8) | data;
	top->wr_tgl ^= 1;
	clk(8);
}

static long n_ne, n_all;
static std::vector<int> hr, he;   // RTL and reference, left, of a note
static double run(int n, double &se, double &sr, int &mx) {
	for (int i = 0; i < n; i++) {
		ymfm::ymf262::output_data out;
		chip->generate(&out, 1);
		top->tick_tgl ^= 1;
		clk(600);
		int r_[2] = { 2 * ((int)(top->out_l << 12) >> 12), 2 * ((int)(top->out_r << 12) >> 12) };   // 20-bit signed
		hr.push_back(r_[0]); he.push_back(out.data[0]);
		int *r = r_;
		for (int c = 0; c < 2; c++) {
			int e = out.data[c];
			double d = r[c] - e;
			se += d * d; sr += (double)e * e;
			if (std::abs(r[c] - e) > mx) mx = std::abs(r[c] - e);
			if (r[c] != e) n_ne++;
			n_all++;
		}
	}
	return 0;
}

int main(int argc, char **argv) {
	if (argc < 2) { fprintf(stderr, "usage: tb_fm patches.txt\n"); return 1; }
	FILE *f = fopen(argv[1], "r");
	if (!f) { perror(argv[1]); return 1; }
	intf io;
	chip = new ymfm::ymf262(io);
	chip->reset();
	top = new Vopl3_fm;
	top->reset_a = 1; clk(20);
	top->reset_a = 0; clk(1200);    // the init writes of opl3_fm: 40..55 = 3F, 80..95 = 0F in both banks
	for (int b = 0; b < 2; b++)
		for (int a = 0; a < 256; a++) {
			int d = (a >= 0x40 && a <= 0x55) ? 0x3f : (a >= 0x80 && a <= 0x95) ? 0x0f : -1;
			if (d >= 0) { chip->write(b ? 2 : 0, a); chip->write(b ? 3 : 1, d); }
		}
	wr(1, 0x05, 0x01);              // OPL3 mode (NEW)
	static const int notes[3][2] = { {2, 0x2ae}, {4, 0x244}, {6, 0x16b} };
	unsigned p[11];
	int np = 0;
	double tse = 0, tsr = 0;
	while (fscanf(f, "%x %x %x %x %x %x %x %x %x %x %x", &p[0], &p[1], &p[2], &p[3], &p[4], &p[5], &p[6], &p[7],
	              &p[8], &p[9], &p[10]) == 11) {
		static const int regs[10] = { 0x20, 0x23, 0x40, 0x43, 0x60, 0x63, 0x80, 0x83, 0xe0, 0xe3 };
		for (int i = 0; i < 10; i++) wr(0, regs[i], p[i]);
		wr(0, 0xc0, (p[10] & 0x0f) | 0x30);
		for (int k = 0; k < 3; k++) {
			double se = 0, sr = 0; int mx = 0;
			hr.clear(); he.clear();
			long ne0 = n_ne, na0 = n_all;
			wr(0, 0xa0, notes[k][1] & 0xff);
			wr(0, 0xb0, 0x20 | (notes[k][0] << 2) | (notes[k][1] >> 8));
			run(3000, se, sr, mx);
			wr(0, 0xb0, (notes[k][0] << 2) | (notes[k][1] >> 8));
			run(1000, se, sr, mx);
			{   // the note as raw int32 pairs (RTL, reference) for an analysis: dump/pNN_nK.raw
				char fn[64]; snprintf(fn, sizeof fn, "dump/p%02d_n%d.raw", np, k);
				FILE *o = fopen(fn, "wb");
				if (o) { for (size_t i = 0; i < hr.size(); i++) { int32_t v[2] = { hr[i], he[i] }; fwrite(v, 4, 2, o); } fclose(o); }
			}
			double lag_e[5] = {0}; int best = 2;
			for (int l = -2; l <= 2; l++) {
				for (size_t i = 2; i + 2 < hr.size(); i++) { double d = hr[i] - he[i + l]; lag_e[l + 2] += d * d; }
				if (lag_e[l + 2] < lag_e[best]) best = l + 2;
			}
			double lr = 0; for (size_t i = 2; i + 2 < he.size(); i++) lr += (double)he[i] * he[i];
			printf("  best lag %+d: %6.1f dB (lag 0 %6.1f dB)\n", best - 2, 10 * log10((lag_e[best] + 1e-9) / (lr + 1e-9)),
			       10 * log10((lag_e[2] + 1e-9) / (lr + 1e-9)));
			printf("patch %2d note %d: ref rms %7.1f  diff rms %7.1f (%6.1f dB)  max %5d  not equal %ld of %ld\n",
			       np, k, sqrt(sr / (na0 ? 1 : 1) / (n_all - na0)), sqrt(se / (n_all - na0)),
			       sr > 0 ? 10 * log10((se + 1e-9) / sr) : 0.0, mx, n_ne - ne0, n_all - na0);
			tse += se; tsr += sr;
		}
		np++;
	}
	printf("patches %d: diff %.1f dB of the reference, not equal %ld of %ld samples\n", np,
	       tsr > 0 ? 10 * log10((tse + 1e-9) / tsr) : 0.0, n_ne, n_all);
	delete top;
	return 0;
}
