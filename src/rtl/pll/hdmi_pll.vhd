-- HDMI PLL STACK FOR SPARTAN 6
-- Copyright 2023 Alvin Albrecht
--
-- This file is part of the ZX Spectrum Next Project
-- <https://gitlab.com/SpectrumNext/ZX_Spectrum_Next_FPGA/tree/master/cores>
--
-- The ZX Spectrum Next FPGA source code is free software: you can 
-- redistribute it and/or modify it under the terms of the GNU General 
-- Public License as published by the Free Software Foundation, either 
-- version 3 of the License, or (at your option) any later version.
--
-- The ZX Spectrum Next FPGA source code is distributed in the hope 
-- that it will be useful, but WITHOUT ANY WARRANTY; without even the 
-- implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
-- PURPOSE.  See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with the ZX Spectrum Next FPGA source code.  If not, see 
-- <https://www.gnu.org/licenses/>.

-- Generates HDMI clocks locked to various Spectrum models' video frames.

-- Updated by Andy Karpov to support more input clocks for FT812 IC

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity hdmi_pll is
   port
   (
      RST         : in std_logic;    -- disable hdmi clocks
      
      -- drp

      SSTEP       : in std_logic;    -- restart hdmi clocks (rising edge)
      CLKDRP      : in std_logic;    -- control logic clock
      
      -- video frame
      
		FREQ			: in std_logic_vector(7 downto 0);    -- input freq from frequency counter, in MHz

      -- clk

      CLKIN       : in std_logic;    --  8/28 MHz muxed
      CLKIN_RDY_N : in std_logic;    -- input clock locked
      
      CLK0OUT     : out std_logic;   -- HDMI Pixelclock (x5) MHz
      CLK1OUT     : out std_logic;   -- HDMI Pixelclock (x5) MHz inv
      CLK2OUT     : out std_logic;   -- Pixelclock MHz
      
      VALID       : out std_logic    -- indicates hdmi clocks functioning
   );
end entity;

architecture rtl of hdmi_pll is

   signal hdmi_reset           : std_logic := '1';
   
   signal sstep_int            : std_logic_vector(1 downto 0) := (others => '0');
   signal sen                  : std_logic;
   
   signal v_pll_reset          : std_logic_vector(3 downto 0) := (others => '1');
   signal pll_reset            : std_logic;
   
   signal vframe               : std_logic_vector(3 downto 0);
   
   type   state_t              is (S_0, S_P1, S_P2, S_W3, S_RUN);
   signal state                : state_t := S_0;
   signal state_next           : state_t;
   
   signal dcm1_res             : std_logic;
   signal dcm2_res             : std_logic;
   signal pll3_res             : std_logic;
   
   signal progdcm              : std_logic;
   signal mux_locked           : std_logic;
   signal mux_progdone         : std_logic;
   signal done                 : std_logic;
   signal progen               : std_logic;
   signal progdata             : std_logic;
   
   signal clk1_direct          : std_logic;
   signal dcm1_locked          : std_logic;
   signal dcm1_progen          : std_logic;
   signal dcm1_progdone        : std_logic;
   
   signal clk1                 : std_logic;
   
   signal clk2                 : std_logic;
   signal dcm2_locked          : std_logic;
   signal dcm2_progen          : std_logic;
   signal dcm2_progdone        : std_logic;
   
   signal pll3_fb              : std_logic;
   signal pll3_locked          : std_logic;
   signal clkhdmi              : std_logic;
   signal clkhdmi5             : std_logic;
   signal clkhdmi5n            : std_logic;

   signal locked               : std_logic := '0';
   signal locked_hdmi          : std_logic := '0';

begin

   -- reset hdmi clocks

   process (CLKDRP)
   begin
      if rising_edge(CLKDRP) then
         hdmi_reset <= RST;
      end if;
   end process;

   process (CLKDRP)
   begin
      if rising_edge(CLKDRP) then
         sstep_int <= SSTEP & sstep_int(1);
      end if;
   end process;
   
   sen <= sstep_int(1) and not sstep_int(0);

   process (CLKDRP)
   begin
      if rising_edge(CLKDRP) then
         if CLKIN_RDY_N = '1' or hdmi_reset = '1' or sen = '1' or state_next = S_0 then
            v_pll_reset <= (others => '1');
         elsif pll_reset = '1' then
            v_pll_reset <= v_pll_reset - 1;
         end if;
      end if;
   end process;

   pll_reset <= '1' when v_pll_reset /= 0 else '0';

   -- video frame selection
   
   process (CLKDRP)
   begin
      if rising_edge(CLKDRP) then
         if pll_reset = '1' then
				case (FREQ) is
					when x"1C" => vframe <= "0000"; -- 28
					when x"18" => vframe <= "0001"; -- 8 (24)
					when x"20" => vframe <= "0010"; -- 8 (32)
					when x"28" => vframe <= "0011"; -- 8 (40)
					when x"30" => vframe <= "0100"; -- 8 (48)
					when x"38" => vframe <= "0101"; -- 8 (56)
					when x"40" => vframe <= "0110"; -- 8 (64)
					when x"48" => vframe <= "0111"; -- 8 (72)
					when x"50" => vframe <= "1000"; -- 8 (80)
					when others => vframe <= "0000";
				end case;
         end if;
      end if;
   end process;

   -- state machine

   process (CLKDRP)
   begin
      if rising_edge(CLKDRP) then
         if pll_reset = '1' then
            state <= S_0;
         else
            state <= state_next;
         end if;
      end if;
   end process;

   process (state, done, pll3_locked)
   begin
      case state is
         when S_0 =>
            state_next <= S_P1;
         when S_P1 =>
            if done = '0' then
               state_next <= S_P1;
            else
               state_next <= S_P2;
            end if;
         when S_P2 =>
            if done = '0' then
               state_next <= S_P2;
            else
               state_next <= S_W3;
            end if;
         when S_W3 =>
            if pll3_locked = '0' then
               state_next <= S_W3;
            else
               state_next <= S_RUN;
            end if;
         when S_RUN =>
            state_next <= S_RUN;
         when others =>
            state_next <= S_0;
      end case;
   end process;

   -- control signals

   dcm1_res <= '1' when state = S_0 else '0';
   dcm2_res <= '1' when dcm1_res = '1' or state = S_P1 else '0';
   pll3_res <= '1' when dcm2_res = '1' or state = S_P2 else '0';
   
   progdcm <= '1' when state = S_P1 or state = S_P2 else '0';
   
   -- program dcm
   
   mux_locked <= dcm2_locked when dcm2_res = '0' else dcm1_locked;
   mux_progdone <= dcm2_progdone when dcm2_res = '0' else dcm1_progdone;

   dcm_prog : entity work.drp_dcm
   port map
   (
      RESET        => pll_reset, 
      
      START        => progdcm,
      DONE         => done,
      FRAME        => vframe,
      
      PROGCLK      => CLKDRP,
      PROGEN       => progen,
      PROGDATA     => progdata,
      PROGDONE     => mux_progdone,
      LOCKED       => mux_locked
   );

   dcm1_progen <= progen when state = S_P1 else '0';
   dcm2_progen <= progen when state = S_P2 else '0';

   -- instantiate clock chain

   dcm_1 : DCM_CLKGEN
   generic map
   (
      CLKFX_MULTIPLY => 10,       -- Multiply value - M - (2-256)
      CLKFX_DIVIDE   => 10,      -- Divide value - D - (1-256)
      CLKFX_MD_MAX   => 5.5,     -- Specify maximum M/D ratio for timing analysis
      CLKIN_PERIOD   => 13.0     -- Input clock period specified in nS (28 MHz)
   )
   port map
   (
      RST       => dcm1_res,     -- 1-bit input: Reset input pin

      CLKIN     => CLKIN,        -- 1-bit input: Input clock

      CLKFX     => clk1_direct,  -- 1-bit output: Generated clock output
      CLKFX180  => open,         -- 1-bit output: Generated clock output 180 degree out of phase from CLKFX.
      CLKFXDV   => open,         -- 1-bit output: Divided clock output

      LOCKED    => dcm1_locked,  -- 1-bit output: Locked output
      STATUS    => open,         -- 2-bit output: DCM_CLKGEN status
      FREEZEDCM => '0',          -- 1-bit input: Prevents frequency adjustments to input clock

      PROGCLK   => CLKDRP,       -- 1-bit input: Clock input for M/D reconfiguration
      PROGEN    => dcm1_progen,  -- 1-bit input: Active high program enable
      PROGDATA  => progdata,     -- 1-bit input: Serial data input for M/D reconfiguration
      PROGDONE  => dcm1_progdone -- 1-bit output: Active high output to indicate the successful re-programming
   );

	--clk1 <= clk1_direct;
	clk1_buf: BUFG
	port map(
		I => clk1_direct,
		O => clk1
	);

   dcm_2 : DCM_CLKGEN
   generic map
   (
      CLKFX_MULTIPLY => 10,      -- Multiply value - M - (2-256)
      CLKFX_DIVIDE   => 10,       -- Divide value - D - (1-256)
      CLKFX_MD_MAX   => 5.5,     -- Specify maximum M/D ratio for timing analysis
      CLKIN_PERIOD   => 13.0    -- Input clock period specified in nS   (28 MHz)
   )
   port map
   (
      RST       => dcm2_res,     -- 1-bit input: Reset input pin

      CLKIN     => clk1,         -- 1-bit input: Input clock

      CLKFX     => clk2,         -- 1-bit output: Generated clock output
      CLKFX180  => open,         -- 1-bit output: Generated clock output 180 degree out of phase from CLKFX.
      CLKFXDV   => open,         -- 1-bit output: Divided clock output

      LOCKED    => dcm2_locked,  -- 1-bit output: Locked output
      STATUS    => open,         -- 2-bit output: DCM_CLKGEN status
      FREEZEDCM => '0',          -- 1-bit input: Prevents frequency adjustments to input clock

      PROGCLK   => CLKDRP,       -- 1-bit input: Clock input for M/D reconfiguration
      PROGEN    => dcm2_progen,  -- 1-bit input: Active high program enable
      PROGDATA  => progdata,     -- 1-bit input: Serial data input for M/D reconfiguration
      PROGDONE  => dcm2_progdone -- 1-bit output: Active high output to indicate the successful re-programming
   );

   pll_3 : PLL_BASE
   generic map
   (
      BANDWIDTH          => "OPTIMIZED",           -- "HIGH", "LOW" or "OPTIMIZED"
      COMPENSATION       => "SYSTEM_SYNCHRONOUS",  -- "SYSTEM_SYNCHRONOUS", "SOURCE_SYNCHRONOUS", "EXTERNAL"
      REF_JITTER         => 0.1,                   -- Reference Clock Jitter in UI (0.000-0.999).
      RESET_ON_LOSS_OF_LOCK => FALSE,              -- Must be set to FALSE
  
      CLKIN_PERIOD       => 13.0,                  -- Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz)
      CLKFBOUT_MULT      => 10,                    -- Multiply value for all CLKOUT clock outputs (1-64)
      DIVCLK_DIVIDE      => 1,                     -- Division value for all output clocks (1-52)
      
      CLKFBOUT_PHASE     => 0.0,                   -- Phase offset in degrees of the clock feedback output (0.0-360.0)
      CLK_FEEDBACK       => "CLKFBOUT",            -- Clock source to drive CLKFBIN ("CLKFBOUT" or "CLKOUT0")
      
      -- CLKOUT0_DIVIDE - CLKOUT5_DIVIDE: Divide amount for CLKOUT# clock output (1-128)
  
      CLKOUT0_DIVIDE     => 2,
      CLKOUT1_DIVIDE     => 2,
      CLKOUT2_DIVIDE     => 10,
      CLKOUT3_DIVIDE     => 10,
      CLKOUT4_DIVIDE     => 10,
      CLKOUT5_DIVIDE     => 10,
 
      -- CLKOUT0_DUTY_CYCLE - CLKOUT5_DUTY_CYCLE: Duty cycle for CLKOUT# clock output (0.01-0.99)
  
      CLKOUT0_DUTY_CYCLE => 0.5,
      CLKOUT1_DUTY_CYCLE => 0.5,
      CLKOUT2_DUTY_CYCLE => 0.5,
      CLKOUT3_DUTY_CYCLE => 0.5,
      CLKOUT4_DUTY_CYCLE => 0.5,
      CLKOUT5_DUTY_CYCLE => 0.5,
      
      -- CLKOUT0_PHASE - CLKOUT5_PHASE: Output phase relationship for CLKOUT# clock output (-360.0-360.0)
  
      CLKOUT0_PHASE      => 0.0,
      CLKOUT1_PHASE      => 180.0,
      CLKOUT2_PHASE      => 0.0,
      CLKOUT3_PHASE      => 0.0,
      CLKOUT4_PHASE      => 0.0,
      CLKOUT5_PHASE      => 0.0
   )
   port map
   (
      RST      => pll3_res,   -- 1-bit input: Reset input
  
      CLKIN    => clk2,       -- 1-bit input: Clock input
  
      CLKOUT0  => clkhdmi5,   -- 1-bit output: Clock output
      CLKOUT1  => clkhdmi5n,  -- 1-bit output: Clock output
      CLKOUT2  => clkhdmi,    -- 1-bit output: Clock output
      CLKOUT3  => open,       -- 1-bit output: Clock output
      CLKOUT4  => open,       -- 1-bit output: Clock output
      CLKOUT5  => open,       -- 1-bit output: Clock output
  
      CLKFBIN  => pll3_fb,    -- 1-bit input: Feedback clock input
      CLKFBOUT => pll3_fb,    -- 1-bit output: PLL_BASE feedback output
  
      LOCKED   => pll3_locked -- 1-bit output: PLL_BASE lock status output
   );

   -- deliver hdmi clocks glitch free

   process (CLKDRP)
   begin
      if rising_edge(CLKDRP) then
         if state = S_RUN then
            locked <= '1';
         else
            locked <= '0';
         end if;
      end if;
   end process;
   
   process (clkhdmi, locked)
   begin
      if locked = '0' then
         locked_hdmi <= '0';
      elsif rising_edge(clkhdmi) then
         locked_hdmi <= '1';
      end if;
   end process;
   
   BUFG_CLKHDMI   : BUFGCE
   port map
   (
      CE => locked_hdmi,
      I  => clkhdmi,
      O  => CLK2OUT
   );

   BUFG_CLKHDMI5  : BUFGCE
   port map
   (
      CE => locked_hdmi,
      I  => clkhdmi5,
      O  => CLK0OUT
   );

   BUFG_CLKHDMI5N : BUFGCE_1
   port map
   (
      CE => locked_hdmi,
      I  => clkhdmi5n,
      O  => CLK1OUT
   );
	
	--CLK0OUT <= clkhdmi5;
	--CLK1OUT <= clkhdmi5n;
	--CLK2OUT <= clkhdmi;
   
   VALID <= locked_hdmi;

end architecture;

