
library ieee;                                   
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity VGA_Sync is
	port(
		rst : in std_logic;
		clk : in std_logic;
		
		blank_n : out std_logic;
		hs : out std_logic;
		vs : out std_logic
	);
end VGA_Sync;

architecture behv of VGA_Sync is
	
	constant hori_line    : integer := 800;
	constant hori_back    : integer := 144;
	constant hori_front   : integer := 16;
	constant vert_line    : integer := 525;
	constant vert_back    : integer := 34;
	constant vert_front   : integer := 11;
	constant h_sync_cycle : integer := 96;
	constant v_sync_cycle : integer := 2;
	
	signal h_cnt : integer range 0 to 2047;
	signal v_cnt : integer range 0 to 1023;
	
	signal cHD  : std_logic;
	signal cVD  : std_logic;
	signal cDEN : std_logic;
	
	signal h_valid : std_logic;
	signal v_valid : std_logic;
	
	
	begin
		process(clk, rst)
			begin
				if rst = '1' then
					h_cnt <= 0;
					v_cnt <= 0;
				else
					if(clk'event and clk = '1') then
						if h_cnt = (hori_line - 1) then
							h_cnt <= 0;
							if v_cnt = (vert_line - 1) then
								v_cnt <= 0;
							else
								v_cnt <= v_cnt + 1;
							end if;
						else
							h_cnt <= h_cnt + 1;
						end if;
					end if;
				end if;
		end process;
		
		cHD <= '0' when (h_cnt < h_sync_cycle) else '1';
		cVD <= '0' when (v_cnt < v_sync_cycle) else '1';
		
		h_valid <= '1' when ((h_cnt < (hori_line - hori_front)) and 
		                     (h_cnt >= hori_back)) else '0';
					  
		v_valid <= '1' when ((v_cnt < (vert_line - vert_front)) and 
		                     (v_cnt >= vert_back)) else '0';		
		
		cDEN <= h_valid and v_valid;
		
		process(clk)
			begin
				if(clk'event and clk='1') then
					hs      <= cHD;
					vs      <= cVD;
					blank_n <= cDEN;
				end if;
		end process;
end behv;