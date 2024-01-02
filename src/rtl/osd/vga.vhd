library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

entity vga_sync is
    Port ( CLK : in  STD_LOGIC;
           HSYNC : out  STD_LOGIC;
           VSYNC : out  STD_LOGIC;
			  BLANK : out STD_LOGIC;
			  HPOS : out std_logic_vector(11 downto 0);
			  VPOS : out std_logic_vector(11 downto 0);
			  SHIFT : buffer std_logic_vector(7 downto 0)
	 );
end vga_sync;

architecture Behavioral of vga_sync is

-- ModeLine " 640x 480@60Hz"  25.20  640  656  752  800  480  490  492  525 -HSync -VSync
-- ModeLine " 720x 480@60Hz"  27.00  720  736  798  858  480  489  495  525 -HSync -VSync
-- Modeline " 800x 600@60Hz"  40.00  800  840  968 1056  600  601  605  628 +HSync +VSync
-- Modeline "1024x 600@60Hz"  48.96 1024 1064 1168 1312  600  601  604  622 -HSync +Vsync
-- ModeLine "1024x 768@60Hz"  65.00 1024 1048 1184 1344  768  771  777  806 -HSync -VSync
-- ModeLine "1280x 720@60Hz"  74.25 1280 1390 1430 1650  720  725  730  750 +HSync +VSync
-- ModeLine "1280x 768@60Hz"  80.14 1280 1344 1480 1680  768  769  772  795 +HSync +VSync
-- ModeLine "1280x 800@60Hz"  83.46 1280 1344 1480 1680  800  801  804  828 +HSync +VSync
-- ModeLine "1280x 960@60Hz" 108.00 1280 1376 1488 1800  960  961  964 1000 +HSync +VSync
-- ModeLine "1280x1024@60Hz" 108.00 1280 1328 1440 1688 1024 1025 1028 1066 +HSync +VSync
-- ModeLine "1360x 768@60Hz"  85.50 1360 1424 1536 1792  768  771  778  795 -HSync -VSync
-- ModeLine "1920x1080@25Hz"  74.25 1920 2448 2492 2640 1080 1084 1089 1125 +HSync +VSync
-- ModeLine "1920x1080@30Hz"  89.01 1920 2448 2492 2640 1080 1084 1089 1125 +HSync +VSync

-- Horizontal Timing constants  
constant h_pixels_across	: integer := 720 - 1;
constant h_sync_on		: integer := 736 - 1;
constant h_sync_off		: integer := 798 - 1;
constant h_end_count		: integer := 850 - 1;
-- Vertical Timing constants
constant v_pixels_down		: integer := 480 - 1;
constant v_sync_on		: integer := 489 - 1;
constant v_sync_off		: integer := 495 - 1;
constant v_end_count		: integer := 525 - 1;

signal hcnt		: std_logic_vector(11 downto 0) := "000000000000"; 	-- horizontal pixel counter
signal vcnt		: std_logic_vector(11 downto 0) := "000000000000"; 	-- vertical line counter
signal red		: std_logic_vector(7 downto 0);
signal green		: std_logic_vector(7 downto 0);
signal blue		: std_logic_vector(7 downto 0);
signal clk_vga		: std_logic;

begin

process (clk, hcnt)
begin
	if clk'event and clk = '1' then
		if hcnt = h_end_count then
			hcnt <= (others => '0');
		else
			hcnt <= hcnt + 1;
		end if;
		if hcnt = h_sync_on then
			if vcnt = v_end_count then
				vcnt <= (others => '0');
				shift <= shift + 1;
			else
				vcnt <= vcnt + 1;
			end if;
		end if;
	end if;
end process;

hsync	<= '1' when (hcnt <= h_sync_on) or (hcnt > h_sync_off) else '0';
vsync	<= '1' when (vcnt <= v_sync_on) or (vcnt > v_sync_off) else '0';
blank	<= '1' when (hcnt > h_pixels_across) or (vcnt > v_pixels_down) else '0';
hpos <= hcnt;
vpos <= vcnt;

end Behavioral;

