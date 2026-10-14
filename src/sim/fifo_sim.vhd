-- Simulation-only VHDL model of rtl/fifo/fifo.v (the queue to the mcu in mcu.vhd), same
-- behaviour: registered dout on rd, empty when the pointers are equal, full one entry early.
-- ISim cannot elaborate the verilog module with an unconnected port from VHDL; synthesis uses fifo.v.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity fifo is
	generic (
		ADDR_WIDTH : integer := 8;
		DATA_WIDTH : integer := 8
	);
	port (
		clk   : in  std_logic;
		reset : in  std_logic;
		rd    : in  std_logic;
		wr    : in  std_logic;
		din   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
		dout  : out std_logic_vector(DATA_WIDTH-1 downto 0);
		full  : out std_logic;
		empty : out std_logic
	);
end fifo;

architecture sim of fifo is
	constant DEPTH : integer := 2**ADDR_WIDTH;
	type mem_t is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
	signal mem : mem_t;
	signal rptr, wptr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
	signal is_full, is_empty : std_logic;
begin
	is_empty <= '1' when wptr = rptr else '0';
	is_full <= '1' when wptr + 1 = rptr else '0';
	empty <= is_empty;
	full <= is_full;

	process (clk, reset)
	begin
		if reset = '1' then
			rptr <= (others => '0');
			wptr <= (others => '0');
		elsif rising_edge(clk) then
			if wr = '1' and is_full = '0' then
				mem(to_integer(wptr)) <= din;
				wptr <= wptr + 1;
			end if;
			if rd = '1' and is_empty = '0' then
				dout <= mem(to_integer(rptr));
				rptr <= rptr + 1;
			end if;
		end if;
	end process;
end sim;
