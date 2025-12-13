module freq_counter(
	input wire clk_ref,
	input wire clk_8,
	input wire clk_test,
	input wire vdac2_sel,
	input wire reset,
	output wire freq
);

parameter fs_ref = 28000000;

/*
tslabs:
типа каунтер от фт клочится, а читаешь его на клоке 8. скока насчитало - такой у тебя и коэфф умножения
тока ресинк сделать, чтоб не было метастабов
через 1 рег
*/

reg [15:0] cnt;
always @(posedge clk_test) begin
	cnt <= cnt + 1;
end

reg [15:0] cnt_r, prev_cnt_r;
reg [8:0] freq;
always @(posedge clk_8) begin
	cnt_r <= cnt;
	prev_cnt_r <= cnt_r;
	freq <= 8*(cnt_r - prev_cnt_r);
end

endmodule
