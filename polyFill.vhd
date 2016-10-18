
library ieee;                                   
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity polyFill is
	port(
		clk : in std_logic;
		rst : in std_logic;
		
		strb : out std_logic
	);
end polyFill;

architecture behv of polyFill is

	component drawPolygon is
		generic(
			UFEI_MANTISSA : natural;
			UFEI_EXPONENT : natural
		);
		port(
			clk : in std_logic;
			rst : in std_logic;
			
			p_x0 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_y0 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_x1 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_y1 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_x2 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			p_y2 : in signed(UFEI_MANTISSA+UFEI_EXPONENT-1 downto 0);
			
			col_r : in std_logic_vector(3 downto 0);
			col_g : in std_logic_vector(3 downto 0);
			col_b : in std_logic_vector(3 downto 0);
			
			strb : out std_logic
		);
	end component;
	component VGA_Sync is
		port(
			rst : in std_logic;
			clk : in std_logic;
			
			blank_n : out std_logic;
			hs : out std_logic;
			vs : out std_logic
		);
	end component;
	
	
	begin
	
		-- 10,10  50,20, 13,100
		
		--fill_block : drawPolygon 
	--		generic map(16, 8)
	--		port map(clk, rst, "000000000000101000000000", 
	--								 "000000000000101000000000", 
	--								 "000000000011001000000000", 
	--								 "000000000001010000000000", 
	--								 "000000000000110100000000", 
	--								 "000000000110010000000000", "0000", "0000", "0000", '0');

	
	
  -- 200.3,10.1    50.4,20.1     13.5,100.9
		fill_block : drawPolygon 
			generic map(18, 8)
			port map(clk, rst, "00000000001100100001001101", 
          								 "00000000000000101000011010", 
									 "00000000000011001001100110", 
									 "00000000000001010000011010", 
									 "00000000000000110110000000", 
									 "00000000000110010011100110", "0000", "0000", "0000", strb);



end behv;