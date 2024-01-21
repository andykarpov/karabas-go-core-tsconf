library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity overlay is
	generic (
		WIDTH		: integer := 720;
		HEIGHT   : integer := 480
	);
	port (
		CLK_BUS	: in std_logic;
		CLK_VGA	: in std_logic;
		OSD_RGB 	: out std_logic_vector(23 downto 0);
		OSD_ACTIVE : out std_logic;
		OSD_HS	: out std_logic;
		OSD_VS	: out std_logic;		
		OSD_COMMAND 	: in std_logic_vector(15 downto 0)
	);
end entity;

architecture rtl of overlay is

    signal video_on : std_logic;
	 signal rgb: std_logic_vector(23 downto 0);

    signal attr, attr2: std_logic_vector(7 downto 0);

    signal char_x: std_logic_vector(2 downto 0);
    signal char_y: std_logic_vector(2 downto 0);

    signal rom_addr: std_logic_vector(10 downto 0);
    signal row_addr: std_logic_vector(2 downto 0);
    signal bit_addr: std_logic_vector(2 downto 0);
    signal font_word: std_logic_vector(7 downto 0);
    signal font_reg : std_logic_vector(15 downto 0);	 
    signal pixel: std_logic;
	 signal pixel_reg: std_logic;
    
    signal addr_read: std_logic_vector(9 downto 0);
    signal addr_write: std_logic_vector(9 downto 0);
    signal vram_di: std_logic_vector(15 downto 0);
    signal vram_do: std_logic_vector(15 downto 0);
    signal vram_wr: std_logic_vector(0 downto 0) := "0";

    signal flash : std_logic;
    signal is_flash : std_logic;
    signal rgb_fg : std_logic_vector(23 downto 0);
    signal rgb_bg : std_logic_vector(23 downto 0);

    signal selector : std_logic_vector(3 downto 0);
	 signal last_osd_command : std_logic_vector(15 downto 0);
	 signal char_buf : std_logic_vector(7 downto 0);
	 signal paper : std_logic := '0';
	 signal paper2 : std_logic := '0';

	 signal hcnt_i : std_logic_vector(11 downto 0) := (others => '0');
	 signal vcnt_i : std_logic_vector(11 downto 0) := (others => '0');
	 signal blank : std_logic;
	 signal hsync : std_logic;
	 signal vsync : std_logic;
	 signal shift : std_logic_vector(7 downto 0);
	 
	 signal hcnt : std_logic_vector(11 downto 0) := (others => '0');
	 signal vcnt : std_logic_vector(11 downto 0) := (others => '0');
	 
	 signal osd_overlay: std_logic := '0';
	 signal osd_popup: std_logic := '0';
	 
	 constant paper_start_h : natural := 0;
	 constant paper_end_h : natural := 8*32; -- 32 characters in a row
	 constant paper_start_v : natural := 0;
	 constant paper_end_v : natural := 8*26; -- 26 character lines
	 constant paper_offset_h : natural := (WIDTH/2 - paper_end_h)/2 - 8 + 4; -- offset from left
	 constant paper_offset_v : natural := (HEIGHT/2 - paper_end_v)/2 - 8; -- offset from top
begin

	U_VGA: entity work.vga_sync
	port map(
		CLK => CLK_VGA,
		HSYNC => hsync,
		VSYNC => vsync,
		BLANK => blank,
		HPOS => hcnt_i,
		VPOS => vcnt_i,
		SHIFT => shift
	);

	OSD_ACTIVE <= osd_overlay or osd_popup;
	OSD_HS <= hsync;
	OSD_VS <= vsync;

	 -- 8x8 FONT
	 U_FONT: entity work.rom_font
    port map (
        addra  => rom_addr,
        clka   => CLK_VGA,
        douta  => font_word
    );

	rgb(23 downto 16)  <= (hcnt_i(7 downto 0) + shift) and "11111111" when blank = '0' else "00000000";
	rgb(15 downto 8)   <= (vcnt_i(7 downto 0) + shift) and "11111111" when blank = '0' else "00000000";
	rgb(7 downto 0)    <= (hcnt_i(7 downto 0) + vcnt_i(7 downto 0) - shift) and "11111111" when blank = '0' else "00000000";

	 --  OSD VRAM
    U_VRAM: entity work.osd_vram 
    port map (
        dina   => vram_di,
        addra  => addr_write,
        clka   => CLK_BUS,
        wea    => vram_wr,

        addrb  => addr_read,
        clkb   => CLK_VGA,
        doutb  => vram_do
    );

	 flash <= '0';
	 hcnt <= '0' & hcnt_i(11 downto 1) - paper_offset_h;
	 vcnt <= '0' & vcnt_i(11 downto 1) - paper_offset_v;

    char_x <= hcnt(2 downto 0);
    char_y <= VCNT(2 downto 0);
	 
	 paper2 <= '1' when hcnt >= paper_start_h and hcnt < paper_end_h and vcnt >= paper_start_v and vcnt < paper_end_v else '0'; 
	 paper <= '1' when hcnt >= paper_start_h + 8 and hcnt < paper_end_h + 8 and vcnt >= paper_start_v and vcnt < paper_end_v else '0'; --        (8 px)
    video_on <= '1' when osd_overlay = '1' else '0';
	 
	 process (CLK_VGA, vram_do)
	 begin
		if (rising_edge(CLK_VGA)) then 
			case (hcnt(2 downto 0)) is
				when "101" =>
					--if (paper2 = '1') then
						addr_read <= VCNT(7 downto 3) & HCNT(7 downto 3);
					--end if;
				when "110" => 
					attr2 <= vram_do(7 downto 0);
					rom_addr <= vram_do(15 downto 8) & char_y;
				when "111" =>
					--attr <= attr2;
				when others => null;						
			end case;
			
			if (hcnt_i(3 downto 0) = "1111") then 
				attr <= attr2;
				font_reg <= font_word(7) & font_word(7) & 
								font_word(6) & font_word(6) & 
								font_word(5) & font_word(5) & 
								font_word(4) & font_word(4) & 
								font_word(3) & font_word(3) & 
								font_word(2) & font_word(2) & 
								font_word(1) & font_word(1) & 
								font_word(0) & font_word(0);
			else 
				font_reg <= font_reg(14 downto 0) & '0';				
			end if;
			
		end if;
	 end process;
	 
	 pixel_reg <= font_reg(15);
	 
    --  RGB
    is_flash <= '1' when attr(3 downto 0) = "0001" else '0';
    selector <= video_on & pixel_reg & flash & is_flash;
    rgb_fg <= (attr(7) and attr(4)) & attr(7) & attr(7) & "00000" &
				  (attr(6) and attr(4)) & attr(6) & attr(6) & "00000" &
				  (attr(5) and attr(4)) & attr(5) & attr(5) & "00000";
    rgb_bg <= (attr(3) and attr(0)) & attr(3) & attr(3) & "00000" &
	           (attr(2) and attr(0)) & attr(2) & attr(2) & "00000" &
				  (attr(1) and attr(0)) & attr(1) & attr(1) & "00000";
				  
    OSD_RGB <= 
				rgb_fg when paper = '1' and (selector="1111" or selector="1001" or selector="1100" or selector="1110") else 
            rgb_bg(23 downto 21) & RGB(23 downto 19) & 
				rgb_bg(16 downto 14) & RGB(16 downto 12) & 
				rgb_bg(7 downto 5) & RGB(7 downto 3) when paper = '1' and (selector="1011" or selector="1101" or selector="1000" or selector="1010") else 
				--"000" & RGB(23 downto 19) & "000" & RGB(16 downto 12) & "000" & RGB(7 downto 3) when video_on = '1' else 
				RGB;

		--   MCU'  SPI
		process(CLK_BUS, osd_command, last_osd_command)
		begin
			  if rising_edge(CLK_BUS) then
					 vram_wr <= "0";
					 if (osd_command /= last_osd_command) then 
						last_osd_command <= osd_command;
						case osd_command(15 downto 8) is 
						  when x"01" => vram_wr <= "0"; osd_overlay <= osd_command(0); -- osd
						  when x"02" => vram_wr <= "0"; osd_popup <= osd_command(0); -- popup
						  when X"10"  => vram_wr <= "0"; addr_write(4 downto 0) <= osd_command(4 downto 0); -- x: 0...32
						  when X"11" => vram_wr <= "0"; addr_write(9 downto 5) <= osd_command(4 downto 0); -- y: 0...32
						  when X"12"  => vram_wr <= "0"; char_buf <= osd_command(7 downto 0); -- char
						  when X"13"  => vram_wr <= "1"; vram_di <= char_buf & osd_command(7 downto 0); -- attrs
						  when others => vram_wr <= "0";
						end case;
					 end if;
			  end if;
		end process;

end architecture;
