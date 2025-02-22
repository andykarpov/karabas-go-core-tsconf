-- zhdmi_tmds_serializer_spartan6.vhd - serializer for DVI/HDMI output (Spartan 6 series)
--
-- Copyright (c) 2025 Andy Karpov <andy dot karpov at gmail dot com>
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library unisim;
use unisim.vcomponents.all;

entity tmds_serializer is
	port (
		clk    : in std_logic;
		clk2x  : in std_logic;
		sclk   : in std_logic;		-- serial clock; frequency = 5 times clk
		strobe : in std_logic;
		reset  : in std_logic;
		tmds_d : in std_logic_vector(9 downto 0);
		tx_d_n : out std_logic;
		tx_d_p : out std_logic
	);
end tmds_serializer;

architecture rtl of tmds_serializer is
	signal tx_d        : std_logic;
	signal phase       : std_logic := '0';
   signal output_bits : std_logic_vector(4 downto 0);	
begin

--	process (clk2x, reset)
--   begin
--		if reset = '1' then
--			phase <= '0';
--			output_bits <= (others => '0'); 
--      elsif rising_edge(clk2x) then
--			if phase = '1' then 
--				output_bits <= tmds_d(9 downto 5);
--			else
--				output_bits <= tmds_d(4 downto 0);
--			end if;
--			phase <= not phase;
--      end if;
--   end process;
	
	convertor: entity work.convert_10to5_fifo
	port map(
		rst => reset,
		clk => clk,
		clkx2 => clk2x,
		datain => tmds_d,
		dataout => output_bits
	);

	serializer: entity work.serdes_n_to_1
	generic map (
		SF => 5
	)
	port map (
		iob_data_out => tx_d,
		ioclk => sclk,
		serdesstrobe => strobe,
		gclk => clk2x,
		reset => reset,
		datain => output_bits
	);

	output_buf: OBUFDS
	port map (
		I =>  tx_d,    -- Buffer input
		O =>  tx_d_p,  -- Diff_p output (connect directly to top-level port)
		OB => tx_d_n   -- Diff_n output (connect directly to top-level port)
	);

end architecture;
