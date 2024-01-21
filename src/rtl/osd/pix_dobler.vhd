library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity pix_doubler is
	port (
		CLK	: in std_logic;
		LOAD	: in std_logic;
		D		: in std_logic_vector(7 downto 0);
		QUAD 	: in std_logic := '0';
		DOUT	: out std_logic
	);
end entity;

architecture rtl of pix_doubler is
	signal shift_16 : std_logic_vector(15 downto 0);
	signal shift_32 : std_logic_vector(31 downto 0);
	signal cnt : std_logic_vector(3 downto 0);
begin

	process(CLK)
	begin
		if rising_edge(CLK) then
			if LOAD = '1' then 
				
				shift_16 <= D(7) & D(7) & 
								D(6) & D(6) & 
								D(5) & D(5) & 
								D(4) & D(4) & 
								D(3) & D(3) & 
								D(2) & D(2) & 
								D(1) & D(1) & 
								D(0) & D(0);
								
				shift_32 <= D(7) & D(7) & D(7) & D(7) & 
								D(6) & D(6) & D(6) & D(6) & 
								D(5) & D(5) & D(5) & D(5) & 
								D(4) & D(4) & D(4) & D(4) & 
								D(3) & D(3) & D(3) & D(3) & 
								D(2) & D(2) & D(2) & D(2) & 
								D(1) & D(1) & D(1) & D(1) & 
								D(0) & D(0) & D(0) & D(0);
								
				cnt <= "0000";				
			else 
				shift_16 <= shift_16(14 downto 0) & '0';
				shift_32 <= shift_32(30 downto 0) & '0';
				cnt <= cnt + 1;
			end if;
		end if;
	end process;
	
	DOUT <= shift_32(31) when QUAD = '1' else shift_16(15);

end architecture;
