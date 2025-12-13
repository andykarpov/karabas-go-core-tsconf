// i2s receiver from esp32

module i2s_receiver(
    input wire reset,
	 input wire clk,
	 input wire bck,
	 input wire lrck,
	 input wire data,
	 output wire [15:0] left,
	 output wire [15:0] right
);

reg ws_d;
reg wsp;

always @(posedge bck) begin
	 ws_d <= lrck;
end

always @(posedge bck) begin
    if (lrck != ws_d)
		wsp <= 1'b1;
	 else
		wsp <= 1'b0;
end

reg sck_d;
always @(posedge clk) begin
    if (reset)
	     sck_d <= 1'b0;
    else 
	     sck_d <= bck;
end

wire sck_re = bck && !sck_d;
wire sck_fe = sck_d && !bck;

reg wsp_e;
always @(posedge clk) begin
    if (reset)
	     wsp_e <= 1'b0;
	 else
	     wsp_e <= wsp;
end

// bit receiver
reg [15:0] receiver;
reg [3:0] recv_count;
always @(posedge clk) begin
    if (reset) begin
	     receiver <= 16'b0;
		  recv_count <= 15;
	 end 
	 else if (sck_re) begin
	     if (wsp_e) begin 
		      receiver[15] <= data;
				receiver[14:0] <= 15'b0;
				recv_count <= 15;
		  end 
		  else begin
		      receiver[recv_count] <= data;
				if (recv_count != 0)
				    recv_count <= recv_count - 1;
		  end
	 end	     
end

// l/r load
reg [15:0] recv_l, recv_r;
always @(posedge clk) begin
    if (reset) begin
	     recv_l <= 16'b0;
		  recv_r <= 16'b0;
	 end
	 else begin
	     if (sck_fe && wsp) begin
		      if (~lrck)
				    recv_r <= receiver[15:0];
				else
				    recv_l <= receiver[15:0];
		  end
	 end
end

// assign output
assign left = recv_l;
assign right = recv_r;

endmodule
