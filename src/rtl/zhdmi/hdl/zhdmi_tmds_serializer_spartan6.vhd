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
		sclk   : in std_logic;		-- serial clock; frequency = 5 times clk
		sclk_n : in std_logic;
		reset  : in std_logic;
		tmds_d : in std_logic_vector(9 downto 0);
		tx_d_n : out std_logic;
		tx_d_p : out std_logic
	);
end tmds_serializer;

architecture rtl of tmds_serializer is
	signal tx_d        : std_logic;
	signal shiftin1    : std_logic;
	signal shiftin2    : std_logic;	
	signal mod5        : std_logic_vector(2 downto 0);
   signal shift_r     : std_logic_vector(9 downto 0);
   signal output_bits : std_logic_vector(1 downto 0);	
begin

	process (sclk, reset)
   begin
		if reset = '1' then
			mod5 <= "000";
			shift_r <= (others => '0');
      elsif rising_edge(sclk) then
         if mod5(2) = '1' then
            mod5    <= "000";
            shift_r <= tmds_d;
         else
            mod5    <= mod5 + "001";
            shift_r <= "00" & shift_r(9 downto 2);
         end if;
      end if;
   end process;

   output_bits <= shift_r(1 downto 0);

	serializer: ODDR2
      generic map (
         DDR_ALIGNMENT => "C0",
         INIT          => '0',
         SRTYPE        => "ASYNC"
      )
      port map (
         C0  => sclk,
         C1  => sclk_n,
         CE  => '1',
         R   => '0',
         S   => '0',
         D0  => output_bits(0),
         D1  => output_bits(1),
         Q   => tx_d
      );

	output_buf: OBUFDS
	generic map (
		IOSTANDARD => "TMDS_33", -- Specify the output I/O standard
		SLEW => "FAST")          -- Specify the output slew rate
	port map (
		I =>  tx_d,    -- Buffer input
		O =>  tx_d_p,  -- Diff_p output (connect directly to top-level port)
		OB => tx_d_n   -- Diff_n output (connect directly to top-level port)
	);

end architecture;
