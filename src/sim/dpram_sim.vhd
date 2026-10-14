-- Simulation-only VHDL model of rtl/ram/dpram.v (the rtc register ram in mcu.vhd).
-- ISim cannot elaborate the verilog module with an open port from VHDL; synthesis uses dpram.v.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity dpram is
	generic (
		DATAWIDTH : integer := 8;
		ADDRWIDTH : integer := 8
	);
	port (
		clock     : in  std_logic;
		address_a : in  std_logic_vector(ADDRWIDTH-1 downto 0);
		data_a    : in  std_logic_vector(DATAWIDTH-1 downto 0);
		wren_a    : in  std_logic;
		q_a       : out std_logic_vector(DATAWIDTH-1 downto 0);
		address_b : in  std_logic_vector(ADDRWIDTH-1 downto 0);
		data_b    : in  std_logic_vector(DATAWIDTH-1 downto 0);
		wren_b    : in  std_logic;
		q_b       : out std_logic_vector(DATAWIDTH-1 downto 0)
	);
end dpram;

architecture sim of dpram is
	type mem_t is array (0 to 2**ADDRWIDTH-1) of std_logic_vector(DATAWIDTH-1 downto 0);
	shared variable mem : mem_t := (others => (others => '0'));
begin
	process (clock)
	begin
		if rising_edge(clock) then
			if is_x(address_a) then
				q_a <= (others => '0'); -- uninitialised address before the first rtc access
			elsif wren_a = '1' then
				mem(to_integer(unsigned(address_a))) := data_a;
				q_a <= data_a;
			else
				q_a <= mem(to_integer(unsigned(address_a)));
			end if;
		end if;
	end process;

	process (clock)
	begin
		if rising_edge(clock) then
			if is_x(address_b) then
				q_b <= (others => '0');
			elsif wren_b = '1' then
				mem(to_integer(unsigned(address_b))) := data_b;
				q_b <= data_b;
			else
				q_b <= mem(to_integer(unsigned(address_b)));
			end if;
		end if;
	end process;
end sim;
