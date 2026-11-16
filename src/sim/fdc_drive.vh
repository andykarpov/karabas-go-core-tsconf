// fdc_drive.vh: the drive of tb_hrdy_fdc and tb_fdc_z80s, included in the module of the testbench: the head
// (STEP / DIRC, TR00, from track 3), one MFM track (track 0, side 0, sector 1 of 256 bytes, sector[]) played in a
// loop at 250 kbit/s x SPEED with a jitter, the index pulse, and the WDATA stream decoded back (wbuf[] to compare
// with, wgot[] / wcount the bytes after the mark). The testbench declares FDC_* (hrdy_fdc), errors, SPEED.
// head position, the times of the steps
integer track = 3, steps = 0;
realtime step_t0 = 0, step_t1 = 0;
assign FDC_TR00 = (track == 0);
always @(posedge FDC_STEP) begin
	track = FDC_DIR ? track + 1 : (track > 0 ? track - 1 : 0);
	steps = steps + 1;
	step_t0 = step_t1;
	step_t1 = $realtime;
end

// ---- the track: MFM channel words ----
function [15:0] crc_byte(input [15:0] crc, input [7:0] b);
	integer i;
	begin
		crc_byte = crc ^ {b, 8'h00};
		for (i = 0; i < 8; i = i + 1)
			crc_byte = crc_byte[15] ? {crc_byte[14:0], 1'b0} ^ 16'h1021 : {crc_byte[14:0], 1'b0};
	end
endfunction

reg [7:0] sector [0:255];
reg [7:0] tbytes [0:1023];
reg       tsync  [0:1023];
reg [15:0] chan  [0:1023];
integer tlen = 0;

task put(input [7:0] b, input s);
	begin tbytes[tlen] = b; tsync[tlen] = s; tlen = tlen + 1; end
endtask

task build_track;
	integer i;
	reg [15:0] crc;
	reg prev;
	reg [7:0] b;
	begin
		for (i = 0; i < 256; i = i + 1) sector[i] = (i * 7 + 8'h35) ^ (i >> 3);
		for (i = 0; i < 40; i = i + 1) put(8'h4E, 0);
		for (i = 0; i < 12; i = i + 1) put(8'h00, 0);
		crc = 16'hFFFF;
		for (i = 0; i < 3; i = i + 1) begin put(8'hA1, 1); crc = crc_byte(crc, 8'hA1); end
		put(8'hFE, 0); crc = crc_byte(crc, 8'hFE);
		put(8'h00, 0); crc = crc_byte(crc, 8'h00);   // C
		put(8'h00, 0); crc = crc_byte(crc, 8'h00);   // H
		put(8'h01, 0); crc = crc_byte(crc, 8'h01);   // R
		put(8'h01, 0); crc = crc_byte(crc, 8'h01);   // N: 256
		put(crc[15:8], 0); put(crc[7:0], 0);
		for (i = 0; i < 22; i = i + 1) put(8'h4E, 0);
		for (i = 0; i < 12; i = i + 1) put(8'h00, 0);
		crc = 16'hFFFF;
		for (i = 0; i < 3; i = i + 1) begin put(8'hA1, 1); crc = crc_byte(crc, 8'hA1); end
		put(8'hFB, 0); crc = crc_byte(crc, 8'hFB);
		for (i = 0; i < 256; i = i + 1) begin put(sector[i], 0); crc = crc_byte(crc, sector[i]); end
		put(crc[15:8], 0); put(crc[7:0], 0);
		for (i = 0; i < 60; i = i + 1) put(8'h4E, 0);
		// MFM: a clock bit between two data zeros; the sync A1 with the missing clock: 4489
		prev = 1'b0;
		for (i = 0; i < tlen; i = i + 1) begin
			b = tbytes[i];
			if (tsync[i])
				chan[i] = 16'h4489;
			else
				chan[i] = {!prev && !b[7], b[7], !b[7] && !b[6], b[6], !b[6] && !b[5], b[5], !b[5] && !b[4], b[4],
				           !b[4] && !b[3], b[3], !b[3] && !b[2], b[2], !b[2] && !b[1], b[1], !b[1] && !b[0], b[0]};
			prev = b[0];
		end
	end
endtask

// the disk turns: flux transitions (200 ns pulses, jitter 0..120 ns), index pulse 1 ms per revolution
real CELL = 2000.0 * SPEED;
integer seed = 1;
initial begin : disk
	integer i, k, j;
	#1;
	build_track;
	forever begin
		FDC_INDEX = 1'b1;
		fork begin #1000000; FDC_INDEX = 1'b0; end join_none
		for (i = 0; i < tlen; i = i + 1)
			for (k = 15; k >= 0; k = k - 1)
				if (chan[i][k]) begin
					j = {$random(seed)} % 121;
					#(j); FDC_RDATA = 1'b1; #200; FDC_RDATA = 1'b0; #(CELL - 200 - j);
				end else
					#(CELL);
	end
end

// ---- the written stream decoded back: cells of 2 us, sync 4489 x 3, FB, 256 bytes, CRC ----
reg [7:0] wbuf [0:255];
reg [7:0] wgot [0:257];
integer wcount = 0, wstate = 0, wbits = 0;
reg [47:0] wsr = 48'd0;
realtime wprev = 0;
reg wfirst = 1'b1;
function [7:0] mfm_data(input [15:0] w);
	mfm_data = {w[14], w[12], w[10], w[8], w[6], w[4], w[2], w[0]};
endfunction
always @(negedge FDC_WG) wfirst = 1'b1;
always @(posedge FDC_WR_DATA) if (FDC_WG) begin : wdec
	integer n, i;
	if (wfirst) begin
		wfirst = 1'b0; wstate = 0;
		n = 1;
	end else
		n = ($realtime - wprev) / 2000.0;   // number of cells since the last transition (real -> integer rounds)
	wprev = $realtime;
	for (i = 0; i < n; i = i + 1) begin
		wsr = {wsr[46:0], i == n - 1};
		if (wstate == 0) begin
			if (wsr == {16'h4489, 16'h4489, 16'h4489}) begin wstate = 1; wbits = 0; end
		end else begin
			wbits = wbits + 1;
			if (wbits == 16) begin
				wbits = 0;
				if (wstate == 1) begin
					if (mfm_data(wsr[15:0]) != 8'hFB) begin
						$display("tb_hrdy_fdc: written mark %h, expected FB", mfm_data(wsr[15:0]));
						errors = errors + 1;
					end
					wstate = 2; wcount = 0;
				end else if (wstate == 2 && wcount < 258) begin
					wgot[wcount] = mfm_data(wsr[15:0]);
					wcount = wcount + 1;
				end
			end
		end
	end
end

