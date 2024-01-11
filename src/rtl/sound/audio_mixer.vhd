-------------------------------------------------------------------------------
-- Audio Mixer
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 
 
entity audio_mixer is
	port ( 
        clk : in std_logic;
        
        mute: in std_logic; -- 1 = mute, 0 - normal
        mode: in std_logic_vector(1 downto 0); -- 00 = ABC, 01 = ACB, 10 = mono

        speaker: in std_logic;
        tape_in: in std_logic;

        ssg0_a: in std_logic_vector(7 downto 0);
        ssg0_b: in std_logic_vector(7 downto 0);
        ssg0_c: in std_logic_vector(7 downto 0);
        ssg1_a: in std_logic_vector(7 downto 0);
        ssg1_b: in std_logic_vector(7 downto 0);
        ssg1_c: in std_logic_vector(7 downto 0);
        
        covox_a: in std_logic_vector(7 downto 0);
        covox_b: in std_logic_vector(7 downto 0);
        covox_c: in std_logic_vector(7 downto 0);
        covox_d: in std_logic_vector(7 downto 0);
        covox_fb: in std_logic_vector(7 downto 0);

        saa_l: in std_logic_vector(7 downto 0);
        saa_r: in std_logic_vector(7 downto 0);
		  
		  gs_l : in std_logic_vector(8 downto 0);
		  gs_r : in std_logic_vector(8 downto 0);

        audio_l : out std_logic_vector(15 downto 0);
        audio_r : out std_logic_vector(15 downto 0)

	);
end audio_mixer;
 
architecture rtl of audio_mixer is
    signal audio_mono		: std_logic_vector(15 downto 0);
begin

process (clk)
begin
    if rising_edge(clk) then
        audio_mono <= 	
				        ("0000" & speaker & "00000000000") +
				        ("00000" & tape_in & "0000000000") +				
				        ("0000"  & ssg0_a &        "0000") + 
				        ("0000"  & ssg0_b &        "0000") + 
				        ("0000"  & ssg0_c &        "0000") + 
				        ("0000"  & ssg1_a &        "0000") + 
				        ("0000"  & ssg1_b &        "0000") + 
				        ("0000"  & ssg1_c &        "0000") + 
				        ("0000"  & covox_a &       "0000") + 
				        ("0000"  & covox_b &       "0000") + 
				        ("0000"  & covox_c &       "0000") + 
				        ("0000"  & covox_d &       "0000") + 
				        ("0000"  & covox_fb &      "0000") + 
				        ("0000"  & saa_l &         "0000") + 				
				        ("0000"  & saa_r &         "0000") + 
						  ("000"   & gs_l &          "0000") + 
						  ("000"   & gs_r &          "0000");
						  
		  -- mute
		  if mute = '1' then 
			audio_l <= (others => '0');
			audio_r <= (others => '0');

		  -- mono
		  elsif (mode = "10") then 
			audio_l <= audio_mono;
			audio_r <= audio_mono;

		  -- ACB
		  elsif (mode = "01") then 
		   audio_l <= ("000" & speaker & "000000000000") + -- ACB: L = A + C/2
				        ("00000" & tape_in & "0000000000") +	
				        ("000"  & ssg0_a &        "00000") + 
				        ("0000"  & ssg0_c &        "0000") + 
				        ("000"  & ssg1_a &        "00000") + 
				        ("0000"  & ssg1_c &        "0000") + 
				        ("000"  & covox_a &       "00000") + 
				        ("000"  & covox_b &       "00000") + 
				        ("000"  & covox_fb &      "00000") + 
				        ("000"  & saa_l  &        "00000") + 
						  ("00"   & gs_l &          "00000");
			audio_r <= ("000" & speaker & "000000000000") + -- ACB: R = B + C/2
				        ("00000" & tape_in & "0000000000") +	
				        ("000"  & ssg0_b &        "00000") + 
				        ("0000"  & ssg0_c &        "0000") + 
				        ("000"  & ssg1_b &        "00000") + 
				        ("0000"  & ssg1_c &        "0000") + 
				        ("000"  & covox_c &       "00000") + 
				        ("000"  & covox_d &       "00000") + 
				        ("000"  & covox_fb &      "00000") + 
				        ("000"  & saa_r &         "00000") +
						  ("00"   & gs_r &          "00000");
		  -- ABC
		  else 
		   audio_l <= ("000" & speaker & "000000000000") +  -- ABC: L = A + B/2
				        ("00000" & tape_in &    "0000000000") +	
				        ("000"  & ssg0_a &        "00000") + 
				        ("0000"  & ssg0_b &        "0000") + 
				        ("000"  & ssg1_a &        "00000") + 
				        ("0000"  & ssg1_b &        "0000") + 
				        ("000"  & covox_a &       "00000") + 
				        ("000"  & covox_b &       "00000") + 
				        ("000"  & covox_fb &      "00000") + 
				        ("000"  & saa_l  &        "00000") +
						  ("00"   & gs_l &          "00000");
			audio_r <= ("000" & speaker & "000000000000") + -- ABC: R = C + B/2
				        ("00000" & tape_in & "0000000000") +	
				        ("000"  & ssg0_c &        "00000") + 
				        ("0000"  & ssg0_b &        "0000") + 
				        ("000"  & ssg1_c &        "00000") + 
				        ("0000"  & ssg1_b &        "0000") + 
				        ("000"  & covox_c &       "00000") + 
				        ("000"  & covox_d &       "00000") + 
				        ("000"  & covox_fb &      "00000") + 
				        ("000"  & saa_r &         "00000") +
						  ("00"   & gs_r &          "00000");
		  end if;
    end if;
end process;

end rtl;	
