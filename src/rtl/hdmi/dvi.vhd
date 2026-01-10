-- Adapted By MVV

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity dvi is
port (
	CLK	: in std_logic;
	RESET : in std_logic;
	RGB : in std_logic_vector(23 downto 0);
	HSYNC : in std_logic;
	VSYNC : in std_logic;
	DE : in std_logic;
	ENC_RED : out std_logic_vector(9 downto 0);
	ENC_GREEN : out std_logic_vector(9 downto 0);
	ENC_BLUE : out std_logic_vector(9 downto 0)
);
end entity;

architecture rtl of dvi is
	
begin

enc0: entity work.dvi_encoder
port map (
	CLK		=> CLK,
	DATA	=> RGB(7 downto 0), -- blue
	C		=> VSYNC & HSYNC,
	BLANK	=> not DE,
	ENCODED	=> ENC_BLUE);

enc1: entity work.dvi_encoder
port map (
	CLK		=> CLK,
	DATA	=> RGB(15 downto 8), -- green
	C		=> "00",
	BLANK	=> not DE,
	ENCODED	=> ENC_GREEN);

enc2: entity work.dvi_encoder
port map (
	CLK		=> CLK,
	DATA	=> RGB(23 downto 16), -- red
	C		=> "00",
	BLANK	=> not DE,
	ENCODED	=> ENC_RED);

end rtl;